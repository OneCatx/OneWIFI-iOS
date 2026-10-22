import ActivityKit
import XCTest
@testable import Runner

@available(iOS 16.2, *)
@MainActor
final class OtpLiveActivityTests: XCTestCase {
  func testPrepareNeverRequestsAndEndsExisting() async throws {
    let fixture = Fixture()
    let existing = FakeActivity(id: "old", scope: "scope-a", startedAt: fixture.now)
    fixture.backend.values = [existing]
    let first = try await fixture.owner.prepare(scope: "scope-a")
    let second = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(existing.ends, 2)
    XCTAssertEqual(first["state"] as? String, "none")
    XCTAssertEqual(second["state"] as? String, "none")
    XCTAssertEqual(first["activity_id"] as? String, "")
  }

  func testInvalidScopeDoesNotRequest() async {
    let fixture = Fixture()
    do { _ = try await fixture.owner.prepare(scope: ""); XCTFail("empty scope accepted") }
    catch {}
  }

  func testForegroundEntryEndsActivityWithoutRequest() async {
    let fixture = Fixture()
    let existing = FakeActivity(id: "old", scope: "scope-a", startedAt: fixture.now)
    fixture.backend.values = [existing]
    fixture.owner.foregroundEntry()
    for _ in 0..<5 { await Task.yield() }
    XCTAssertEqual(existing.ends, 1)
  }

  func testSnapshotEndsRestoredActivityAndDropsToken() {
    let fixture = Fixture()
    let existing = FakeActivity(id: "live", scope: "scope-a", startedAt: fixture.now)
    fixture.backend.values = [existing]
    fixture.defaults.set([
      "scope_id": "scope-a", "activity_id": "live", "update_token": "aabb",
      "revision": 1, "state": "active",
      "started_at": Int(fixture.now.timeIntervalSince1970),
      "expires_at": Int(fixture.now.addingTimeInterval(28_800).timeIntervalSince1970),
    ], forKey: "onewifi.otp.activity.snapshot")
    let state = fixture.owner.snapshot()
    XCTAssertEqual(state["state"] as? String, "ended")
    XCTAssertEqual(state["update_token"] as? String, "")
  }

  func testEndClearsTokenAndDoesNotRevive() async {
    let fixture = Fixture()
    fixture.defaults.set([
      "scope_id": "scope-a", "activity_id": "live", "update_token": "aabb",
      "revision": 1, "state": "active",
      "started_at": Int(fixture.now.timeIntervalSince1970),
      "expires_at": Int(fixture.now.addingTimeInterval(28_800).timeIntervalSince1970),
    ], forKey: "onewifi.otp.activity.snapshot")
    let existing = FakeActivity(id: "live", scope: "scope-a", startedAt: fixture.now)
    fixture.backend.values = [existing]
    let state = await fixture.owner.end(scope: "scope-a")
    XCTAssertEqual(existing.ends, 1)
    XCTAssertEqual(state["state"] as? String, "ended")
    XCTAssertEqual(state["update_token"] as? String, "")
    XCTAssertEqual(fixture.owner.snapshot()["update_token"] as? String, "")
  }

  func testLegacyActivityIsEndedAndNeverReplaced() async throws {
    let fixture = Fixture()
    let legacy = FakeActivity(id: "legacy", scope: nil, startedAt: nil)
    fixture.backend.values = [legacy]
    let state = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(legacy.ends, 1)
    XCTAssertEqual(state["state"] as? String, "none")
  }

  func testExpiredCodeProjectionNeverReturnsOldCode() {
    let state = OtpActivityContentState(code: "test-code", sender: "", device: "", startedAt: Date())
    XCTAssertEqual(state.displayCode(isStale: true), "")
    XCTAssertEqual(state.displayCode(isStale: false), "test-code")
  }
}

@available(iOS 16.2, *)
@MainActor
private final class Fixture {
  var now = Date(timeIntervalSince1970: 1_790_000_000)
  let backend = FakeBackend()
  let defaults = UserDefaults(suiteName: "otp-tests-\(UUID().uuidString)")!
  lazy var owner = OtpLiveActivity(backend: backend, defaults: defaults,
    now: { [unowned self] in self.now })
}

@available(iOS 16.2, *)
@MainActor
private final class FakeBackend: OtpActivityBackend {
  var values: [FakeActivity] = []
  var activities: [any OtpActivityHandle] { values }
}

@available(iOS 16.2, *)
@MainActor
private final class FakeActivity: OtpActivityHandle {
  let id: String
  let scope: String?
  let startedAt: Date?
  var status: ActivityState = .active
  var ends = 0
  init(id: String, scope: String?, startedAt: Date?) {
    self.id = id; self.scope = scope; self.startedAt = startedAt
  }
  func end() async { ends += 1; status = .ended }
}
