import AVFoundation
import CoreFoundation
import Foundation
import UIKit

/// The sole call owner. All state and edge callbacks are serialized on the main queue.
final class CallKitCoordinator: NSObject {
  private final class Local {
    let uuid = UUID()
    let deviceID: String
    let label: String
    var id: String
    var number: String
    var direction: String
    var state: String
    var startedAt: String?
    var owned = false
    var muted = false
    var requested = false
    var endRequested = false
    var reporting = false
    var seenInSnapshot = false
    var error = ""
    var action: CallSystemAction?
    var claimStarted = false
    var media: CallPCMTransporting?
    var connectedReported = false
    var dtmfReported = false
    var hangupStarted = false
    var hangupResult: Result<Void, Error>?
    var hangupCompletions: [(Result<Void, Error>) -> Void] = []
    init(deviceID: String, label: String, id: String, number: String, direction: String, state: String) {
      self.deviceID = deviceID; self.label = label; self.id = id
      self.number = number; self.direction = direction; self.state = state
    }
  }
  var onSnapshot: (([String: Any]) -> Void)?
  private let platform: CallSystemProviding
  private let gatewayFactory: (CallGatewayConfiguration) -> CallGatewayServing
  private let mediaFactory: (CallGatewayServing, GatewayCall) -> CallPCMTransporting
  private let microphoneGranted: () -> Bool
  private let requestMicrophone: (@escaping (Bool) -> Void) -> Void
  private let schedule: (TimeInterval, DispatchWorkItem) -> Void
  private var gateway: CallGatewayServing?
  private var devices: [GatewayCallDevice] = []
  private var local: Local?
  private var terminal: Set<String> = []
  private var generation = 0
  private var revision = 0
  private var snapshotVersion = 0
  private var status = "unconfigured"
  private var eventStatus = "stopped"
  private var eventError = ""
  private var systemDiagnostic = ""
  private var audioDiagnostic = ""
  private var foreground = true
  private var permission = false
  private var audioActive = false
  private var fresh = false
  private var error = ""
  private var endStatusUUID: UUID?
  private var offlineTimer: DispatchWorkItem?
  private var expiryTimer: DispatchWorkItem?
  private var requestTimer: DispatchWorkItem?
  private var pushBindingTimer: DispatchWorkItem?
  private var endingActions: [UUID: CallSystemAction] = [:]

  override convenience init() {
    self.init(platform: CallKitPlatform(), gatewayFactory: { CallGatewayClient(configuration: $0) },
      mediaFactory: { CallPCMTransport(gateway: $0, call: $1) },
      microphoneGranted: { CallMicrophonePermission.isGranted },
      requestMicrophone: { CallMicrophonePermission.request($0) })
    foreground = UIApplication.shared.applicationState != .background
  }
  init(platform: CallSystemProviding,
       gatewayFactory: @escaping (CallGatewayConfiguration) -> CallGatewayServing,
       mediaFactory: @escaping (CallGatewayServing, GatewayCall) -> CallPCMTransporting,
       microphoneGranted: @escaping () -> Bool,
       requestMicrophone: @escaping (@escaping (Bool) -> Void) -> Void,
       schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
         DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
       }) {
    self.platform = platform; self.gatewayFactory = gatewayFactory; self.mediaFactory = mediaFactory
    self.microphoneGranted = microphoneGranted; self.requestMicrophone = requestMicrophone
    self.schedule = schedule
    permission = microphoneGranted()
    super.init()
    platform.onAction = { [weak self] in self?.perform($0) }
    platform.onAudio = { [weak self] active in
      guard let self else { return }; self.assertMain()
      self.audioActive = active && self.local != nil; self.updateAudio(); self.publish()
    }
    platform.onReset = { [weak self] in
      guard let self else { return }; self.assertMain()
      for action in self.endingActions.values { action.abandon() }
      self.endingActions.removeAll()
      self.local?.action?.abandon()
      self.audioActive = false
      self.finishLocal(reason: .failed, error: "call_system_reset", hangup: true)
      self.endStatusUUID = nil; self.error = "call_system_reset"; self.publish()
    }
    platform.onTimeout = { [weak self] identifier in
      guard let self else { return }
      if let action = self.endingActions.removeValue(forKey: identifier) { action.abandon(); return }
      guard self.local?.action?.identifier == identifier else { return }
      self.local?.action?.abandon()
      self.finishLocal(reason: .failed, error: "call_action_timeout", hangup: true)
    }
  }

  var snapshot: [String: Any] {
    assertMain()
    var value: [String: Any] = ["schemaVersion": 1, "generation": generation, "revision": revision,
      "status": status, "eventStatus": eventStatus, "eventError": eventError, "canReceiveCalls": canReceive,
      "eventDiagnostic": gateway?.eventDiagnostic ?? "", "systemDiagnostic": systemDiagnostic,
      "audioDiagnostic": audioDiagnostic,
      "foreground": foreground, "permissions": ["microphone": permission],
      "devices": devices.map(\.dictionary), "local": NSNull(), "error": error]
    if let l = local {
      let media = l.media?.snapshot ?? [:]
      let ready = media["audioReady"] as? Bool ?? false
      let phase = l.endRequested ? "disconnecting" : (l.state == "active" && !ready ? "connecting_audio" : l.state)
      value["local"] = ["deviceId": l.deviceID, "id": l.id, "number": l.number, "label": l.label,
        "direction": l.direction, "phase": phase, "error": l.error, "muted": l.muted,
        "systemMuted": false, "uuid": l.uuid.uuidString, "owned": l.owned,
        "actionPending": l.requested || l.action != nil || l.reporting,
        "audioReady": ready, "dtmfSupported": media["dtmfSupported"] ?? false,
        "sentFrames": media["sentFrames"] ?? 0, "receivedFrames": media["receivedFrames"] ?? 0,
        "endpoint": media["endpoint"] ?? "receiver", "endpoints": media["endpoints"] ?? [],
        "startedAt": l.startedAt as Any? ?? NSNull()] as [String: Any]
    }
    return value
  }
  private var canReceive: Bool { foreground && status == "configured" && fresh && permission }
  private func assertMain() { dispatchPrecondition(condition: .onQueue(.main)) }
  private func publish() { revision += 1; onSnapshot?(snapshot) }
  private func key(_ device: String, _ id: String) -> String { "\(device.utf8.count):\(device)\(id)" }

  func configure(_ arguments: [String: Any]) throws {
    assertMain()
    let config: CallGatewayConfiguration
    do { config = try CallGatewayConfiguration(arguments: arguments) }
    catch {
      clear()
      if let failure = error as? CallGatewayFailure, case .unauthorized = failure { status = "unauthorized"; eventStatus = "unauthorized"; publish() }
      throw error
    }
    if let old = gateway?.configuration,
       old.origin == config.origin, old.token == config.token,
       old.expiresAt == config.expiresAt, old.certificateFingerprint == config.certificateFingerprint { return }
    clear()
    guard config.expiresAt.map({ $0 > Date() }) ?? true else { status = "unauthorized"; publish(); throw CallGatewayFailure.unauthorized }
    let client = gatewayFactory(config)
    gateway = client; status = "configured"; error = ""; permission = microphoneGranted()
    let epoch = generation
    client.onSnapshot = { [weak self] devices in
      guard let self, self.generation == epoch else { return }; self.receive(devices)
    }
    client.onEventStatus = { [weak self] state in
      guard let self, self.generation == epoch else { return }; self.eventsChanged(state)
    }
    if let expiry = config.expiresAt {
      let task = DispatchWorkItem { [weak self] in
        guard let self, self.generation == epoch else { return }; self.invalidateAuthorization()
      }
      expiryTimer = task
      schedule(max(0, expiry.timeIntervalSinceNow), task)
    }
    // 有活动通话时，事件流在后台也必须保持：推送唤醒的来电需要快照才能
    // 被接起，而 setForeground(false) 只在没有通话时才停流。
    if foreground || local != nil { client.startEvents() }
    publish()
  }

  func clear() {
    assertMain()
    generation += 1
    offlineTimer?.cancel(); offlineTimer = nil
    expiryTimer?.cancel(); expiryTimer = nil
    requestTimer?.cancel(); requestTimer = nil
    pushBindingTimer?.cancel(); pushBindingTimer = nil
    for action in endingActions.values { action.finish(false) }
    endingActions.removeAll()
    finishLocal(reason: .failed, error: "", hangup: true)
    gateway?.invalidate(); gateway = nil
    devices = []; terminal = []; snapshotVersion = 0; fresh = false; audioActive = false
    status = "unconfigured"; eventStatus = "stopped"; eventError = ""; error = ""; endStatusUUID = nil
    systemDiagnostic = ""; audioDiagnostic = ""
    publish()
  }
  private func invalidateAuthorization() {
    clear(); status = "unauthorized"; eventStatus = "unauthorized"; eventError = "call_unauthorized"; error = "call_unauthorized"; publish()
  }
  func setForeground(_ foreground: Bool) {
    assertMain()
    guard self.foreground != foreground else { return }
    self.foreground = foreground
    permission = microphoneGranted()
    // An owned/background call already has a live, watchdog-validated stream.
    // startEvents is idempotent: discarding freshness here could strand it until
    // the next state change, because heartbeats are not full snapshots.
    if foreground { gateway?.startEvents() }
    else { stopIdleEvents() }
    updateAudio(); publish()
  }
  private func stopIdleEvents() {
    if !foreground && local == nil { fresh = false; gateway?.stopEvents(); eventStatus = "stopped" }
  }

  /// VoIP 推送入口，只由 `CallPushRegistry` 调用。
  ///
  /// 与快照路径的区别：推送到达时 App 通常在后台上、没有 SSE 快照，
  /// 因此这里**不受** `canReceive`（前台 + 快照新鲜度）约束——那道门槛
  /// 保护的是快照驱动的上报，用在这里会让后台来电永远报不进 CallKit。
  /// 所有权、生命周期和媒体仍然全部由本类持有。
  func receivePush(
    deviceID: String, callID: String, label: String, number: String,
    completion: @escaping (Error?) -> Void
  ) {
    assertMain()
    guard !deviceID.isEmpty, !callID.isEmpty else { completion(CallGatewayFailure.invalidRequest); return }
    // 同一通电话已由快照上报：这次推送是重复投递。PushKit 要求的「必须
    // 上报一次」已由那次上报满足，再报一次只会凭空多一个来电界面。
    if let l = local, l.deviceID == deviceID, l.id == callID {
      completion(nil)
      return
    }
    // 已经结束，或本机正有另一通电话占用：仍要满足 PushKit 的上报要求，
    // 但立刻结束，绝不留下一个接不起来的振铃。
    if terminal.contains(key(deviceID, callID)) || local != nil {
      let uuid = UUID()
      platform.reportIncoming(uuid: uuid, number: number) { [weak self] _ in
        self?.platform.reportEnded(uuid: uuid, reason: .remoteEnded)
        completion(nil)
      }
      return
    }
    let l = Local(deviceID: deviceID, label: label, id: callID, number: number,
                  direction: "incoming", state: "ringing")
    local = l; error = ""; endStatusUUID = nil; l.reporting = true
    let epoch = generation
    platform.reportIncoming(uuid: l.uuid, number: number) { [weak self] failure in
      guard let self else { completion(nil); return }
      guard self.generation == epoch, self.local === l else {
        if failure == nil { self.platform.reportEnded(uuid: l.uuid, reason: .remoteEnded) }
        completion(nil)
        return
      }
      l.reporting = false
      if let failure {
        self.systemDiagnostic = CallSystemDiagnostic.describe(failure, stage: .incomingReport, kind: nil)
        self.finishLocal(reason: .failed, error: "call_incoming_report", hangup: false)
        completion(failure)
        return
      }
      self.armPushBinding(l, epoch: epoch)
      self.publish()
      completion(nil)
    }
  }

  /// 推送已经在响，但它还缺一个能接通的网关会话：Flutter 需要先完成登录
  /// 态恢复和 `configure`。给这段绑定一个有界的等待，超时就撤掉振铃，
  /// 免得留下一个用户接了却没声音的来电。
  private func armPushBinding(_ l: Local, epoch: Int) {
    let task = DispatchWorkItem { [weak self, weak l] in
      guard let self, let l, self.generation == epoch, self.local === l,
            !l.owned, !l.seenInSnapshot else { return }
      self.finishLocal(reason: .failed, error: "call_gateway_unavailable", hangup: false)
    }
    pushBindingTimer?.cancel()
    pushBindingTimer = task
    schedule(20, task)
  }

  func command(_ method: String, arguments: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
    assertMain()
    if method == "requestPermissions" {
      let epoch = generation
      requestMicrophone { [weak self] granted in DispatchQueue.main.async {
        guard let self, self.generation == epoch else { completion(.failure(CallGatewayFailure.cancelled)); return }
        self.permission = granted; self.updateAudio()
        if granted && self.fresh { self.receive(self.devices) } else { self.publish() }
        completion(granted ? .success(()) : .failure(CallGatewayFailure.invalidRequest))
      } }
      return
    }
    guard let requestedGeneration = arguments["generation"] as? NSNumber,
          CFGetTypeID(requestedGeneration) != CFBooleanGetTypeID(),
          requestedGeneration.doubleValue == Double(generation),
          status == "configured", gateway != nil else { completion(.failure(CallGatewayFailure.cancelled)); return }
    if method == "refreshEvents" {
      guard foreground, terminal.count <= 8192, error != "call_history_limit", eventStatus != "unauthorized" else {
        completion(.failure(CallGatewayFailure.stateConflict)); return
      }
      if eventStatus != "connecting" && eventStatus != "connected" {
        // Only replace the listener. In particular, do not reset the active
        // call's original offline deadline or its ownership/media/history.
        let epoch = generation
        gateway?.stopEvents()
        guard generation == epoch, status == "configured", foreground else {
          completion(.failure(CallGatewayFailure.cancelled)); return
        }
        gateway?.startEvents()
      }
      completion(.success(())); return
    }
    if ["answer", "hangup", "mute", "route", "dtmf"].contains(method) {
      guard let l = local, let uuid = arguments["uuid"] as? String, uuid == l.uuid.uuidString else {
        completion(.failure(CallGatewayFailure.stateConflict)); return
      }
    }
    do {
      let l: Local
      let kind: CallSystemKind
      switch method {
      case "dial":
        guard canReceive, local == nil, let device = arguments["deviceId"] as? String,
              let d = devices.first(where: { $0.id == device && $0.ready }),
              let number = arguments["number"] as? String, !number.isEmpty, number.count <= 128,
              number.allSatisfy({ "+0123456789*# ,;".contains($0) }) else { throw CallGatewayFailure.invalidRequest }
        l = Local(deviceID: device, label: d.label, id: "", number: number, direction: "outgoing", state: "dialing")
        local = l; error = ""; endStatusUUID = nil; kind = .start(number)
      case "answer", "hangup":
        guard let current = local, let device = arguments["deviceId"] as? String,
              let id = arguments["id"] as? String, current.deviceID == device, current.id == id else { throw CallGatewayFailure.stateConflict }
        l = current
        if method == "answer" {
          guard canReceive, l.state == "ringing", !l.reporting else { throw CallGatewayFailure.stateConflict }
          kind = .answer
        } else { kind = .end }
      case "mute":
        guard let current = local, current.owned, let muted = callStrictBool(arguments["muted"]) else { throw CallGatewayFailure.stateConflict }
        l = current; kind = .mute(muted)
      case "dtmf":
        guard let current = local, current.owned, current.state == "active", fresh,
              current.media?.snapshot["dtmfSupported"] as? Bool == true,
              let digit = arguments["digit"] as? String, validDigit(digit) else { throw CallGatewayFailure.dtmfUnavailable }
        l = current; kind = .dtmf(digit)
      case "route":
        guard let current = local, current.owned, let media = current.media,
              let endpoint = arguments["endpoint"] as? String else { throw CallGatewayFailure.stateConflict }
        try media.setRoute(endpoint); publish(); completion(.success(())); return
      default: throw CallGatewayFailure.invalidRequest
      }
      // End is allowed to supersede an in-flight claim; other actions are serialized.
      if l.endRequested || (method != "hangup" && (l.requested || l.action != nil)) { throw CallGatewayFailure.stateConflict }
      if method == "hangup" {
        l.endRequested = true; l.action?.finish(false)
        l.media?.setCaptureEnabled(false); l.media?.stop(); l.media = nil
      }
      l.requested = true; l.error = ""
      let epoch = generation
      publish()
      platform.request(uuid: l.uuid, kind: kind) { [weak self, weak l] failure in
        guard let self, let l, self.generation == epoch, self.local === l else {
          completion(.failure(CallGatewayFailure.cancelled)); return
        }
        if let failure {
          self.systemDiagnostic = CallSystemDiagnostic.describe(failure, stage: .transaction, kind: kind)
          l.requested = false
          if method == "dial" || method == "hangup" { self.finishLocal(reason: .failed, error: "call_system_transaction", hangup: method == "hangup") }
          else { l.error = "call_system_transaction"; self.publish() }
          completion(.failure(CallGatewayFailure.systemTransaction))
        } else { completion(.success(())) }
      }
      armRequestTimeout(l, epoch: epoch)
    } catch { completion(.failure(error)) }
  }
  private func validDigit(_ value: String) -> Bool { value.count == 1 && "0123456789*#ABCD".contains(value) }
  private func armRequestTimeout(_ l: Local, epoch: Int) {
    requestTimer?.cancel()
    let task = DispatchWorkItem { [weak self, weak l] in
      guard let self, let l, self.generation == epoch, self.local === l,
            l.requested || l.action != nil else { return }
      self.finishLocal(reason: .failed, error: "call_action_timeout", hangup: true)
    }
    requestTimer = task
    schedule(15, task)
  }

  private func perform(_ action: CallSystemAction) {
    assertMain()
    guard let l = local, action.uuid == l.uuid, let client = gateway else { action.finish(false); return }
    if case .end = action.kind {
      // Local shutdown cannot wait for network or another outstanding action.
      let shouldEnd = l.owned || l.state == "ringing" || l.state == "answering" || l.hangupStarted
      let id = l.id
      // A dispatched claim with no returned ID is still an unknown remote outcome.
      let awaitingRemoteEnd = (shouldEnd && !id.isEmpty) || l.claimStarted
      finishLocal(reason: .remoteEnded, error: awaitingRemoteEnd ? "call_remote_end_unconfirmed" : "", hangup: false)
      if shouldEnd && !id.isEmpty {
        let epoch = generation
        endingActions[action.identifier] = action
        schedule(15, DispatchWorkItem { [weak self] in
          guard let self, let pending = self.endingActions.removeValue(forKey: action.identifier) else { return }
          pending.finish(false)
        })
        hangupOnce(l, id: id, client: client) { [weak self, uuid = l.uuid] result in
          guard let self, self.generation == epoch else { return }
          // SDK action lifetime and the last end's status have independent owners.
          let pending = self.endingActions.removeValue(forKey: action.identifier)
          switch result {
          case .success: pending?.finish(true)
          case .failure: pending?.finish(false)
          }
          self.completeEndStatus(uuid: uuid, epoch: epoch, result: result)
        }
      } else { action.finish(true) }
      return
    }
    guard !l.endRequested, l.action == nil, status == "configured" else { action.finish(false); return }
    l.requested = false
    switch action.kind {
    case .start:
      // The system takes the app out of the foreground to show its own call UI.
      // The start action itself is the proof that this outgoing call is allowed.
      guard permission, fresh, l.id.isEmpty, !l.owned else { action.finish(false); finishLocal(reason: .failed, error: "call_state_conflict", hangup: false); return }
      l.action = action; platform.reportOutgoing(uuid: l.uuid, connected: false)
      claim(l, action: action, method: "dial", body: ["number": l.number], client: client)
    case .answer:
      guard permission, fresh, l.state == "ringing", !l.owned, !l.reporting else { action.finish(false); publish(); return }
      l.state = "answering"; l.action = action
      claim(l, action: action, method: "answer", body: ["id": l.id], client: client)
    case .mute(let muted):
      guard l.owned else { action.finish(false); publish(); return }
      l.muted = muted; l.media?.setMuted(muted); action.finish(true); publish()
    case .dtmf(let digit):
      guard l.owned, l.state == "active", fresh, validDigit(digit), l.media?.snapshot["dtmfSupported"] as? Bool == true else { action.finish(false); publish(); return }
      l.action = action; l.error = ""; publish()
      let epoch = generation
      client.performAction(deviceID: l.deviceID, action: "dtmf", body: ["id": l.id, "digit": digit]) { [weak self, weak l] result in
        guard let self, let l, self.generation == epoch, self.local === l, l.action === action else { action.finish(false); return }
        l.action = nil
        switch result { case .success: action.finish(true); l.error = ""
        case .failure(let failure):
          action.finish(false); l.error = callFailureCode(failure)
          if let failure = failure as? CallGatewayFailure, case .unauthorized = failure { self.invalidateAuthorization(); return }
        }
        self.publish()
      }
    case .end: break
    }
    if l.action != nil { armRequestTimeout(l, epoch: generation) }
  }

  private func claim(_ l: Local, action: CallSystemAction, method: String, body: [String: String], client: CallGatewayServing) {
    let epoch = generation
    let claimSnapshotVersion = snapshotVersion
    let originalID = l.id
    l.claimStarted = true
    publish()
    client.performAction(deviceID: l.deviceID, action: method, body: body) { [weak self] result in
      guard let self else { action.finish(false); return }
      // Parse an explicit success only; SSE active is never evidence of ownership.
      let parsed = result.flatMap { json -> Result<GatewayCall, Error> in
        do {
          let call = try GatewayCall(deviceID: l.deviceID, json: json)
          try self.validateClaim(call, method: method, originalID: originalID)
          return .success(call)
        }
        catch { return .failure(error) }
      }
      guard self.generation == epoch, self.local === l, l.action === action else {
        action.finish(false)
        // Only a successful, explicitly identified late claim may be compensated.
        if case .success(let call) = parsed {
          self.hangupOnce(l, id: call.id, client: client) { [weak self, uuid = l.uuid] result in
            self?.completeEndStatus(uuid: uuid, epoch: epoch, result: result)
          }
        }
        return
      }
      switch parsed {
      case .failure(let failure):
        action.finish(false); l.action = nil
        if let failure = failure as? CallGatewayFailure, case .unauthorized = failure { self.invalidateAuthorization(); return }
        self.finishLocal(reason: .failed, error: callFailureCode(failure), hangup: false)
      case .success(let call):
        if l.endRequested {
          // Cancellation already won, even if its CXEnd perform has not arrived.
          // Retain only the proven cleanup target, never ownership or media.
          l.id = call.id; l.action = nil; action.finish(false)
          self.hangupOnce(l, id: call.id, client: client); self.publish(); return
        }
        guard !self.terminal.contains(self.key(call.deviceID, call.id)) else {
          action.finish(false); l.action = nil
          self.finishLocal(reason: .remoteEnded, error: "call_state_conflict", hangup: false); return
        }
        // HTTP proves the claim; a newer observed lifecycle must not regress.
        var current = call
        if self.snapshotVersion > claimSnapshotVersion,
           let observed = self.devices.first(where: { $0.id == l.deviceID })?.calls.first(where: { $0.id == call.id }) {
          guard observed.direction == call.direction else {
            action.finish(false); l.action = nil
            self.finishLocal(reason: .failed, error: "call_protocol_violation", hangup: false); return
          }
          l.seenInSnapshot = true
          if self.lifecycleRank(observed.state) >= self.lifecycleRank(call.state) { current = observed }
        }
        l.id = current.id; l.owned = true; l.state = current.state; l.startedAt = current.startedAt
        l.action = nil; action.finish(true)
        self.startMediaIfReady(l, call: current); self.updateAudio(); self.publish()
      }
    }
  }

  private func validateClaim(_ call: GatewayCall, method: String, originalID: String) throws {
    guard !call.isTerminal else { throw CallGatewayFailure.stateConflict }
    if method == "answer" {
      guard call.id == originalID, call.direction == "incoming", call.state == "active" else { throw CallGatewayFailure.protocolViolation }
    } else {
      guard call.direction == "outgoing", ["dialing", "early_media", "active"].contains(call.state) else { throw CallGatewayFailure.protocolViolation }
    }
  }
  private func lifecycleRank(_ state: String) -> Int {
    switch state { case "active": return 3; case "early_media": return 2; case "answering": return 1; default: return 0 }
  }

  private func completeEndStatus(uuid: UUID, epoch: Int, result: Result<Void, Error>) {
    guard generation == epoch else { return }
    // Authentication belongs to this session even when a newer call owns the UI.
    if case .failure(let failure) = result,
       let failure = failure as? CallGatewayFailure, case .unauthorized = failure {
      invalidateAuthorization(); return
    }
    guard endStatusUUID == uuid else { return }
    endStatusUUID = nil
    switch result {
    case .success: error = ""
    case .failure(let failure): error = callFailureCode(failure)
    }
    publish()
  }

  /// One external end per local attempt, shared by system end and late claim cleanup.
  private func hangupOnce(_ l: Local, id: String, client: CallGatewayServing,
                          completion: ((Result<Void, Error>) -> Void)? = nil) {
    if let result = l.hangupResult { completion?(result); return }
    if let completion { l.hangupCompletions.append(completion) }
    guard !l.hangupStarted else { return }
    l.hangupStarted = true
    client.performAction(deviceID: l.deviceID, action: "hangup", body: ["id": id]) { result in
      let result = result.map { _ in () }
      l.hangupResult = result
      let completions = l.hangupCompletions; l.hangupCompletions.removeAll()
      for completion in completions { completion(result) }
    }
  }

  private func receive(_ updated: [GatewayCallDevice]) {
    assertMain()
    guard status == "configured" else { return }
    let present = Set(updated.flatMap { d in d.calls.map { key(d.id, $0.id) } })
    for d in devices { for c in d.calls where !present.contains(key(d.id, c.id)) { terminal.insert(key(d.id, c.id)) } }
    snapshotVersion += 1
    devices = updated; fresh = true; eventStatus = "connected"; eventError = ""
    offlineTimer?.cancel(); offlineTimer = nil
    for d in devices { for c in d.calls where c.isTerminal { terminal.insert(key(d.id, c.id)) } }
    // Bounded anti-resurrection memory: fail closed, never discard tombstones mid-session.
    if terminal.count > 8192 {
      fresh = false
      finishLocal(reason: .failed, error: "call_history_limit", hangup: true)
      gateway?.stopEvents(); eventStatus = "failed"; error = "call_history_limit"; publish(); return
    }
    if let l = local, !l.id.isEmpty {
      let call = devices.first(where: { $0.id == l.deviceID })?.calls.first(where: { $0.id == l.id })
      if let call {
        l.seenInSnapshot = true
        if call.isTerminal || terminal.contains(key(l.deviceID, l.id)) {
          finishLocal(reason: .remoteEnded, error: "", hangup: false)
        } else if !l.owned && l.action == nil && call.state != "ringing" {
          finishLocal(reason: .answeredElsewhere, error: "", hangup: false)
        } else if l.owned {
          l.state = call.state; l.startedAt = call.startedAt
          startMediaIfReady(l, call: call); updateAudio()
        }
      } else if l.seenInSnapshot {
        // Identity deletion revokes even an in-flight answer, not just ringing/owned.
        finishLocal(reason: .remoteEnded, error: "", hangup: false)
      }
    }
    if local == nil && canReceive {
      outer: for d in devices where d.ready {
        for call in d.calls where call.direction == "incoming" && call.state == "ringing" && !call.isTerminal {
          if terminal.contains(key(d.id, call.id)) { continue }
          let l = Local(deviceID: d.id, label: d.label, id: call.id, number: call.number, direction: call.direction, state: "ringing")
          l.seenInSnapshot = true
          local = l; error = ""; endStatusUUID = nil; l.reporting = true
          let epoch = generation
          platform.reportIncoming(uuid: l.uuid, number: call.number) { [weak self] failure in
            guard let self else { return }
            guard self.generation == epoch, self.local === l else {
              if failure == nil { self.platform.reportEnded(uuid: l.uuid, reason: .remoteEnded) }
              return
            }
            l.reporting = false
            if let failure {
              self.systemDiagnostic = CallSystemDiagnostic.describe(failure, stage: .incomingReport, kind: nil)
              self.finishLocal(reason: .failed, error: "call_incoming_report", hangup: false)
            }
            else { self.publish() }
          }
          break outer
        }
      }
    }
    publish()
  }

  private func eventsChanged(_ state: String) {
    assertMain()
    if state == "unauthorized" { invalidateAuthorization(); return }
    eventStatus = state
    eventError = ["connecting", "connected", "stopped"].contains(state) ? "" : (gateway?.eventFailure ?? "")
    if state != "connected" { fresh = false }
    if state == "offline" || state == "stale" || state == "failed" || state == "unavailable" {
      if offlineTimer == nil, local != nil {
        let epoch = generation
        let task = DispatchWorkItem { [weak self] in
          guard let self, self.generation == epoch, !self.fresh else { return }
          self.finishLocal(reason: .failed, error: "call_events_stale", hangup: true)
        }
        offlineTimer = task
        schedule(20, task)
      }
    }
    publish()
  }
  private func startMediaIfReady(_ l: Local, call: GatewayCall) {
    if l.owned, call.state == "active", l.direction == "outgoing", !l.connectedReported {
      l.connectedReported = true; platform.reportOutgoing(uuid: l.uuid, connected: true)
    }
    guard l.owned, !l.endRequested, call.mediaReady, ["active", "early_media", "dialing"].contains(call.state), let gateway else { return }
    if l.media == nil {
      let media = mediaFactory(gateway, call)
      l.media = media
      let epoch = generation
      media.onChange = { [weak self, weak l] in
        guard let self, let l, self.generation == epoch, self.local === l else { return }
        let supported = l.media?.snapshot["dtmfSupported"] as? Bool ?? false
        if l.dtmfReported != supported {
          l.dtmfReported = supported
          self.platform.updateCapabilities(uuid: l.uuid, dtmfSupported: supported)
        }
        self.publish()
      }
      media.onFailure = { [weak self, weak l] code in
        guard let self, let l, self.generation == epoch, self.local === l else { return }
        if code == "call_unauthorized" { self.invalidateAuthorization(); return }
        self.audioDiagnostic = l.media?.snapshot["audioDiagnostic"] as? String ?? ""
        self.finishLocal(reason: .failed, error: code, hangup: true)
      }
      media.setCaptureEnabled(false); media.setMuted(l.muted); media.start()
    }
  }
  private func updateAudio() {
    guard let l = local, let media = l.media else { return }
    let playback = l.owned && !l.endRequested && audioActive && permission && ["active", "early_media", "dialing"].contains(l.state)
    media.setCaptureEnabled(playback && l.state == "active")
    media.setSystemAudioActive(playback)
  }
  private func finishLocal(reason: CallSystemEndReason, error: String, hangup: Bool) {
    guard let l = local else { return }
    local = nil
    audioActive = false
    offlineTimer?.cancel(); offlineTimer = nil
    requestTimer?.cancel(); requestTimer = nil
    pushBindingTimer?.cancel(); pushBindingTimer = nil
    l.media?.setCaptureEnabled(false); l.media?.stop(); l.media = nil
    l.action?.finish(false); l.action = nil
    if !l.id.isEmpty { terminal.insert(key(l.deviceID, l.id)) }
    platform.reportEnded(uuid: l.uuid, reason: reason)
    self.error = error
    endStatusUUID = error == "call_remote_end_unconfirmed" ? l.uuid : nil
    if hangup, l.owned, !l.id.isEmpty {
      if let gateway { hangupOnce(l, id: l.id, client: gateway) }
    }
    stopIdleEvents(); publish()
  }
}
