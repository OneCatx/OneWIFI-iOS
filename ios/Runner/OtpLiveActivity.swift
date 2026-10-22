import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *) @MainActor
protocol OtpActivityHandle: AnyObject {
  var id: String { get }
  var scope: String? { get }
  var startedAt: Date? { get }
  var status: ActivityState { get }
  var token: Data? { get }
  var tokens: AsyncStream<Data> { get }
  var states: AsyncStream<ActivityState> { get }
  func end() async
}

@available(iOS 16.2, *) @MainActor
protocol OtpActivityBackend {
  var enabled: Bool { get }
  var activities: [any OtpActivityHandle] { get }
  func request(scope: String, startedAt: Date) throws -> any OtpActivityHandle
}

@available(iOS 16.2, *) @MainActor
private final class SystemOtpActivity: OtpActivityHandle {
  let activity: Activity<OtpActivityAttributes>
  init(_ activity: Activity<OtpActivityAttributes>) { self.activity = activity }
  var id: String { activity.id }
  var scope: String? { activity.attributes.scopeID }
  var startedAt: Date? { activity.attributes.sessionStartedAt }
  var status: ActivityState { activity.activityState }
  var token: Data? { activity.pushToken }
  var tokens: AsyncStream<Data> {
    AsyncStream { continuation in
      let task = Task { for await value in activity.pushTokenUpdates { continuation.yield(value) }; continuation.finish() }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
  var states: AsyncStream<ActivityState> {
    AsyncStream { continuation in
      let task = Task { for await value in activity.activityStateUpdates { continuation.yield(value) }; continuation.finish() }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
  func end() async {
    let empty = OtpActivityContentState(code: "", sender: "", device: "", startedAt: Date())
    await activity.end(ActivityContent(state: empty, staleDate: Date()), dismissalPolicy: .immediate)
  }
}

@available(iOS 16.2, *) @MainActor
private struct SystemOtpBackend: OtpActivityBackend {
  var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
  var activities: [any OtpActivityHandle] { Activity<OtpActivityAttributes>.activities.map(SystemOtpActivity.init) }
  func request(scope: String, startedAt: Date) throws -> any OtpActivityHandle {
    let state = OtpActivityContentState(code: "", sender: "", device: "", startedAt: startedAt)
    return SystemOtpActivity(try Activity.request(
      attributes: OtpActivityAttributes(scopeID: scope, sessionStartedAt: startedAt),
      content: ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(28_800)), pushType: .token))
  }
}

private enum OtpActivityError: LocalizedError {
  case disabled, background, invalidScope
  var errorDescription: String? {
    switch self {
    case .disabled: return "请在系统设置中允许 OneWIFI 使用实时活动。"
    case .background: return "请打开 OneWIFI 后准备接收活动。"
    case .invalidScope: return "接收活动归属无效。"
    }
  }
}

/// Only explicit foreground preparation requests an empty activity.
/// OTP content is exclusively written by silent server updates.
@available(iOS 16.2, *) @MainActor
final class OtpLiveActivity {
  static let shared = OtpLiveActivity()
  var onState: (([String: Any]) -> Void)?
  private let backend: any OtpActivityBackend
  private let defaults: UserDefaults
  private let now: () -> Date
  private let foreground: () -> Bool
  private var current: (any OtpActivityHandle)?
  private var tokenTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  private var prepareTask: Task<[String: Any], Error>?
  private var generation = 0
  private var suppressed = false
  private var preparingScope = ""
  private var preparationSerial = 0
  private var value: [String: Any]
  private static let snapshotKey = "onewifi.otp.activity.snapshot"
  private static let pendingKey = "onewifi.otp.activity.pendingEnds"

  init(backend: (any OtpActivityBackend)? = nil, defaults: UserDefaults = .standard,
       now: @escaping () -> Date = Date.init,
       foreground: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
    self.backend = backend ?? SystemOtpBackend(); self.defaults = defaults
    self.now = now; self.foreground = foreground
    value = defaults.dictionary(forKey: Self.snapshotKey) ?? Self.empty()
  }
  func foregroundEntry() { suppressed = false }
  func scopeIdentifier(key: String) -> String {
    guard key.count == 64, key.allSatisfy({ $0.isHexDigit }) else { return "" }
    let storageKey = "onewifi.otp.scope.\(key)"
    if let known = defaults.string(forKey: storageKey) { return known }
    let identifier = UUID().uuidString
    defaults.set(identifier, forKey: storageKey)
    return identifier
  }
  func prepare(scope: String) async throws -> [String: Any] {
    guard !scope.isEmpty, scope.count <= 256 else { throw OtpActivityError.invalidScope }
    guard foreground() else { throw OtpActivityError.background }
    guard backend.enabled else { throw OtpActivityError.disabled }
    if let pending = prepareTask {
      let pendingScope = preparingScope
      let result = try await pending.value
      if pendingScope == scope { return result }
      prepareTask = nil
      return try await prepare(scope: scope)
    }
    _ = snapshot()
    if suppressed { return value }
    let epoch = generation
    preparingScope = scope
    preparationSerial += 1
    let serial = preparationSerial
    let pending = Task<[String: Any], Error> { @MainActor in
      let existing = self.backend.activities
      let match = existing.first { self.eligible($0, scope: scope) }
      for activity in existing where activity.id != match?.id {
        await activity.end()
        guard epoch == self.generation, self.foreground() else { return self.value }
      }
      guard epoch == self.generation, self.foreground(), !self.suppressed else { return self.value }
      let selected: any OtpActivityHandle
      if let match { selected = match }
      else { selected = try self.backend.request(scope: scope, startedAt: self.now()) }
      self.observe(selected)
      return self.snapshot()
    }
    prepareTask = pending
    defer {
      if preparationSerial == serial { prepareTask = nil; preparingScope = "" }
    }
    return try await pending.value
  }
  private func eligible(_ activity: any OtpActivityHandle, scope: String) -> Bool {
    if value["activity_id"] as? String == activity.id,
       let state = value["state"] as? String, state == "ended" || state == "dismissed" { return false }
    guard activity.scope == scope, let started = activity.startedAt,
          started.addingTimeInterval(28_800) > now(), started <= now().addingTimeInterval(60) else { return false }
    return activity.status == .active || activity.status == .stale
  }
  func snapshot() -> [String: Any] {
    if let activity = current {
      let exists = backend.activities.contains { $0.id == activity.id }
      if !exists || activity.status == .dismissed || activity.status == .ended {
        terminal(activity.status == .dismissed || !exists ? "dismissed" : "ended")
      } else if let started = activity.startedAt, started.addingTimeInterval(28_800) <= now() {
        terminal("ended"); Task { await activity.end() }
      } else if let token = activity.token { acceptToken(token, id: activity.id, epoch: generation) }
    } else if value["state"] as? String == "active" {
      if let id = value["activity_id"] as? String,
         let activity = backend.activities.first(where: { $0.id == id }),
         eligible(activity, scope: value["scope_id"] as? String ?? "") {
        observe(activity)
      } else {
        terminal("dismissed")
        // Cold launch is a new entry; a missing cached activity may be prepared.
        suppressed = false
      }
    }
    return value
  }
  private func observe(_ activity: any OtpActivityHandle) {
    if current?.id == activity.id { return }
    tokenTask?.cancel(); stateTask?.cancel()
    generation += 1; let epoch = generation
    current = activity
    let same = value["activity_id"] as? String == activity.id
    let started = activity.startedAt ?? now()
    if !same {
      value = ["scope_id": activity.scope ?? "", "activity_id": activity.id,
        "update_token": "", "revision": 1, "state": "active",
        "started_at": Int(started.timeIntervalSince1970),
        "expires_at": Int(started.addingTimeInterval(28_800).timeIntervalSince1970)]
    }
    if let token = activity.token { acceptToken(token, id: activity.id, epoch: epoch) }
    publish()
    tokenTask = Task { [weak self] in
      for await token in activity.tokens {
        guard let self, !Task.isCancelled else { return }
        self.acceptToken(token, id: activity.id, epoch: epoch)
      }
    }
    stateTask = Task { [weak self] in
      for await state in activity.states {
        guard let self, !Task.isCancelled, self.generation == epoch, self.current?.id == activity.id else { return }
        if state == .dismissed || state == .ended { self.terminal(state == .dismissed ? "dismissed" : "ended") }
        // .stale is content freshness, not activity termination.
      }
    }
  }
  private func acceptToken(_ token: Data, id: String, epoch: Int) {
    guard generation == epoch, current?.id == id, value["state"] as? String == "active", !token.isEmpty else { return }
    let hex = token.map { String(format: "%02x", $0) }.joined()
    guard value["update_token"] as? String != hex else { return }
    value["update_token"] = hex
    value["revision"] = min((value["revision"] as? Int ?? 0) + 1, 2_147_483_647)
    publish()
  }
  private func terminal(_ state: String) {
    generation += 1; suppressed = true
    tokenTask?.cancel(); tokenTask = nil; stateTask?.cancel(); stateTask = nil; current = nil
    if value["state"] as? String != state || value["update_token"] as? String != "" {
      value["revision"] = min((value["revision"] as? Int ?? 0) + 1, 2_147_483_647)
    }
    value["state"] = state; value["update_token"] = ""
    if let id = value["activity_id"] as? String, !id.isEmpty {
      var pending = defaults.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
      pending.removeAll { $0["activity_id"] as? String == id }
      pending.append(value)
      defaults.set(pending, forKey: Self.pendingKey)
    }
    publish()
  }
  func pendingEnds(scope: String) -> [[String: Any]] {
    (defaults.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []).filter { $0["scope_id"] as? String == scope }
  }
  func acknowledgeEnd(scope: String, id: String, revision: Int) {
    var pending = defaults.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
    pending.removeAll { $0["scope_id"] as? String == scope && $0["activity_id"] as? String == id && $0["revision"] as? Int == revision }
    defaults.set(pending, forKey: Self.pendingKey)
  }
  func end(scope: String) async -> [String: Any] {
    if preparingScope == scope { generation += 1 }
    // Wrong-scope delayed teardown cannot stop a replacement activity.
    guard value["scope_id"] as? String == scope else { return Self.empty() }
    let existing = backend.activities.filter { $0.scope == scope }
    terminal("ended")
    suppressed = false
    let ended = value
    for activity in existing { await activity.end() }
    return ended
  }
  private func publish() { defaults.set(value, forKey: Self.snapshotKey); onState?(value) }
  private static func empty() -> [String: Any] {
    ["scope_id": "", "activity_id": "", "update_token": "", "revision": 0,
     "started_at": 0, "expires_at": 0, "state": "none"]
  }
}
