import ActivityKit
import Foundation

@available(iOS 16.2, *) @MainActor
protocol OtpActivityHandle: AnyObject {
  var id: String { get }
  var scope: String? { get }
  var startedAt: Date? { get }
  var status: ActivityState { get }
  func end() async
}

@available(iOS 16.2, *) @MainActor
protocol OtpActivityBackend {
  var activities: [any OtpActivityHandle] { get }
}

@available(iOS 16.2, *) @MainActor
private final class SystemOtpActivity: OtpActivityHandle {
  let activity: Activity<OtpActivityAttributes>
  init(_ activity: Activity<OtpActivityAttributes>) { self.activity = activity }
  var id: String { activity.id }
  var scope: String? { activity.attributes.scopeID }
  var startedAt: Date? { activity.attributes.sessionStartedAt }
  var status: ActivityState { activity.activityState }
  func end() async {
    let empty = OtpActivityContentState(code: "", sender: "", device: "", startedAt: Date())
    await activity.end(ActivityContent(state: empty, staleDate: Date()), dismissalPolicy: .immediate)
  }
}

@available(iOS 16.2, *) @MainActor
private struct SystemOtpBackend: OtpActivityBackend {
  var activities: [any OtpActivityHandle] { Activity<OtpActivityAttributes>.activities.map(SystemOtpActivity.init) }
}

private enum OtpActivityError: LocalizedError {
  case invalidScope
  var errorDescription: String? { "接收活动归属无效。" }
}

/// SMS never requests a Live Activity. Calls use CallKit on the island.
/// Preparation only ends a leftover activity and reports an empty snapshot.
@available(iOS 16.2, *) @MainActor
final class OtpLiveActivity {
  static let shared = OtpLiveActivity()
  var onState: (([String: Any]) -> Void)?
  private let backend: any OtpActivityBackend
  private let defaults: UserDefaults
  private let now: () -> Date
  private var value: [String: Any]
  private static let snapshotKey = "onewifi.otp.activity.snapshot"
  private static let pendingKey = "onewifi.otp.activity.pendingEnds"

  init(backend: (any OtpActivityBackend)? = nil, defaults: UserDefaults = .standard,
       now: @escaping () -> Date = Date.init) {
    self.backend = backend ?? SystemOtpBackend(); self.defaults = defaults
    self.now = now
    value = defaults.dictionary(forKey: Self.snapshotKey) ?? Self.empty()
  }
  func foregroundEntry() {
    Task { @MainActor in await retireActivities() }
  }
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
    // SMS stays on ordinary notifications. The island is reserved for calls.
    await retireActivities()
    return Self.empty()
  }
  private func retireActivities() async {
    let existing = backend.activities
    if value["state"] as? String == "active" { terminal("ended") }
    for activity in existing { await activity.end() }
  }
  private func eligible(_ activity: any OtpActivityHandle, scope: String) -> Bool {
    if value["activity_id"] as? String == activity.id,
       let state = value["state"] as? String, state == "ended" || state == "dismissed" { return false }
    guard activity.scope == scope, let started = activity.startedAt,
          started.addingTimeInterval(28_800) > now(), started <= now().addingTimeInterval(60) else { return false }
    return activity.status == .active || activity.status == .stale
  }
  func snapshot() -> [String: Any] {
    let live = backend.activities.filter { $0.status == .active || $0.status == .stale }
    if value["state"] as? String == "active" {
      let matched = live.first { activity in
        eligible(activity, scope: value["scope_id"] as? String ?? "")
      }
      terminal(matched == nil && live.isEmpty ? "dismissed" : "ended")
    }
    for activity in live { Task { await activity.end() } }
    return value
  }
  private func terminal(_ state: String) {
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
    // Wrong-scope delayed teardown cannot stop a replacement activity.
    guard value["scope_id"] as? String == scope else { return Self.empty() }
    let existing = backend.activities.filter { $0.scope == scope }
    terminal("ended")
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
