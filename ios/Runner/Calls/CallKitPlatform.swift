import AVFoundation
import CallKit
import Foundation
import UIKit

enum CallSystemKind {
  case start(String), answer, end, mute(Bool), dtmf(String)
  var diagnosticName: String {
    switch self {
    case .start: return "start"
    case .answer: return "answer"
    case .end: return "end"
    case .mute: return "mute"
    case .dtmf: return "dtmf"
    }
  }
}
enum CallSystemEndReason { case failed, remoteEnded, answeredElsewhere }

/// Only fixed labels and numeric codes cross into UI; NSError descriptions and userInfo may contain caller data.
enum CallSystemDiagnostic {
  enum Stage: String { case transaction, incomingReport }
  static func describe(_ error: Error, stage: Stage, kind: CallSystemKind?,
                       backgroundModes: [String] = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []) -> String {
    let allowedDomains: Set<String> = [
      "com.apple.CallKit.error.requesttransaction", "com.apple.CallKit.error.incomingcall",
      "com.apple.CallKit.error", NSOSStatusErrorDomain, NSCocoaErrorDomain,
    ]
    var lines = ["CK-D1", "stage=\(stage.rawValue) action=\(kind?.diagnosticName ?? "incoming")",
      "backgroundAudio=\(backgroundModes.contains("audio")) backgroundVoIP=\(backgroundModes.contains("voip"))"]
    var current: NSError? = error as NSError
    // Limit traversal even for cyclic or unexpectedly deep underlying errors.
    for index in 0..<3 {
      guard let item = current else { break }
      let domain = allowedDomains.contains(item.domain) ? item.domain : "other"
      lines.append("\(index == 0 ? "error" : "underlying\(index)") domain=\(domain) code=\(item.code)")
      current = item.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return lines.joined(separator: "\n")
  }
}

/// Completion is idempotent, including timeout/reset racing an HTTP response.
final class CallSystemAction {
  let uuid: UUID
  let identifier: UUID
  let kind: CallSystemKind
  private var completion: ((Bool) -> Void)?
  init(uuid: UUID, identifier: UUID = UUID(), kind: CallSystemKind, completion: @escaping (Bool) -> Void) {
    self.uuid = uuid; self.identifier = identifier; self.kind = kind; self.completion = completion
  }
  func finish(_ success: Bool) {
    let callback = completion
    completion = nil
    callback?(success)
  }
  /// The SDK has already invalidated this action (timeout/provider reset).
  /// Do not call fulfill/fail after this point, including from late HTTP results.
  func abandon() { completion = nil }
}

protocol CallSystemProviding: AnyObject {
  var onAction: ((CallSystemAction) -> Void)? { get set }
  var onAudio: ((Bool) -> Void)? { get set }
  var onReset: (() -> Void)? { get set }
  var onTimeout: ((UUID) -> Void)? { get set }
  func request(uuid: UUID, kind: CallSystemKind, completion: @escaping (Error?) -> Void)
  func reportIncoming(uuid: UUID, number: String, completion: @escaping (Error?) -> Void)
  func reportEnded(uuid: UUID, reason: CallSystemEndReason)
  func reportOutgoing(uuid: UUID, connected: Bool)
  func updateCapabilities(uuid: UUID, dtmfSupported: Bool)
}

final class CallKitPlatform: NSObject, CallSystemProviding, CXProviderDelegate {
  var onAction: ((CallSystemAction) -> Void)?
  var onAudio: ((Bool) -> Void)?
  var onReset: (() -> Void)?
  var onTimeout: ((UUID) -> Void)?
  private let provider: CXProvider
  private let controller = CXCallController()
  private var interruptionObserver: NSObjectProtocol?

  override init() {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.phoneNumber, .generic]
    configuration.includesCallsInRecents = false
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: .main)
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
    ) { [weak self] notification in
      guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            type == AVAudioSession.InterruptionType.began.rawValue else { return }
      // Only a subsequent provider didActivate may restore the coordinator's gate.
      self?.onAudio?(false)
    }
  }
  deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }

  func request(uuid: UUID, kind: CallSystemKind, completion: @escaping (Error?) -> Void) {
    let action: CXAction
    switch kind {
    case .start(let number):
      let start = CXStartCallAction(call: uuid, handle: CXHandle(type: .phoneNumber, value: number))
      start.isVideo = false
      // 公开请求没有「把系统通话界面拉到前台」字段。App 还在前台时，先把
      // 自己退到后台，系统才会用这通去电替换当前界面，而不是只在后台登记。
      if UIApplication.shared.applicationState == .active {
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
      }
      action = start
    case .answer: action = CXAnswerCallAction(call: uuid)
    case .end: action = CXEndCallAction(call: uuid)
    case .mute(let muted): action = CXSetMutedCallAction(call: uuid, muted: muted)
    case .dtmf(let digit): action = CXPlayDTMFCallAction(call: uuid, digits: digit, type: .singleTone)
    }
    controller.request(CXTransaction(action: action)) { error in
      DispatchQueue.main.async { completion(error) }
    }
  }

  func reportIncoming(uuid: UUID, number: String, completion: @escaping (Error?) -> Void) {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .phoneNumber, value: number)
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    update.hasVideo = false
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
      DispatchQueue.main.async { completion(error) }
    }
  }

  func reportEnded(uuid: UUID, reason: CallSystemEndReason) {
    let mapped: CXCallEndedReason
    switch reason {
    case .failed: mapped = .failed
    case .remoteEnded: mapped = .remoteEnded
    case .answeredElsewhere: mapped = .answeredElsewhere
    }
    provider.reportCall(with: uuid, endedAt: Date(), reason: mapped)
  }
  func reportOutgoing(uuid: UUID, connected: Bool) {
    if connected { provider.reportOutgoingCall(with: uuid, connectedAt: Date()) }
    else {
      let update = CXCallUpdate()
      update.supportsHolding = false; update.supportsGrouping = false
      update.supportsUngrouping = false; update.hasVideo = false; update.supportsDTMF = false
      provider.reportCall(with: uuid, updated: update)
      provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    }
  }
  func updateCapabilities(uuid: UUID, dtmfSupported: Bool) {
    let update = CXCallUpdate()
    update.supportsHolding = false; update.supportsGrouping = false
    update.supportsUngrouping = false; update.hasVideo = false
    update.supportsDTMF = dtmfSupported
    provider.reportCall(with: uuid, updated: update)
  }
  private func configureAudio() throws {
    // CallKit is the sole owner of activation. Configuring category is not activation.
    try AVAudioSession.sharedInstance().setCategory(
      .playAndRecord, mode: .voiceChat, options: [CallAudioOptions.bluetooth])
  }
  private func deliver(_ action: CXCallAction, kind: CallSystemKind) {
    let wrapped = CallSystemAction(uuid: action.callUUID, identifier: action.uuid, kind: kind) { success in
      if success { action.fulfill() } else { action.fail() }
    }
    guard let onAction else { wrapped.finish(false); return }
    onAction(wrapped)
  }
  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    do { try configureAudio(); deliver(action, kind: .start(action.handle.value)) } catch { action.fail() }
  }
  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    do { try configureAudio(); deliver(action, kind: .answer) } catch { action.fail() }
  }
  func provider(_ provider: CXProvider, perform action: CXEndCallAction) { deliver(action, kind: .end) }
  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) { deliver(action, kind: .mute(action.isMuted)) }
  func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) { deliver(action, kind: .dtmf(action.digits)) }
  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) { action.fail() }
  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) { onTimeout?(action.uuid) }
  func providerDidReset(_ provider: CXProvider) { onReset?() }
  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) { onAudio?(true) }
  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { onAudio?(false) }
}
