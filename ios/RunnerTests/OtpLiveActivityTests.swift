import ActivityKit
import XCTest
@testable import Runner

@available(iOS 16.2, *)
@MainActor
final class OtpLiveActivityTests: XCTestCase {
  func testDuplicatePrepareRequestsOnceAndKeepsDeadline() async throws {
    let fixture = Fixture()
    let first = try await fixture.owner.prepare(scope: "scope-a")
    fixture.now = fixture.now.addingTimeInterval(30)
    let second = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(fixture.backend.requests, 1)
    XCTAssertEqual(first["expires_at"] as? Int, second["expires_at"] as? Int)
  }

  func testBackgroundCannotCreate() async {
    let fixture = Fixture()
    fixture.foreground = false
    do { _ = try await fixture.owner.prepare(scope: "scope-a"); XCTFail("background accepted") }
    catch {}
    XCTAssertEqual(fixture.backend.requests, 0)
  }

  func testDismissedActivityDoesNotReviveUntilForegroundEntry() async throws {
    let fixture = Fixture()
    _ = try await fixture.owner.prepare(scope: "scope-a")
    fixture.backend.values[0].status = .dismissed
    _ = fixture.owner.snapshot()
    _ = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(fixture.backend.requests, 1)
    fixture.owner.foregroundEntry()
    _ = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(fixture.backend.requests, 2)
  }

  func testStaleActivityIsReused() async throws {
    let fixture = Fixture()
    _ = try await fixture.owner.prepare(scope: "scope-a")
    fixture.backend.values[0].status = .stale
    _ = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(fixture.backend.requests, 1)
  }

  func testEndClearsTokenAndLateTokenCannotRevive() async throws {
    let fixture = Fixture()
    _ = try await fixture.owner.prepare(scope: "scope-a")
    let value = fixture.backend.values[0]
    value.token = Data([0xaa, 0xbb])
    _ = fixture.owner.snapshot()
    _ = await fixture.owner.end(scope: "scope-a")
    value.tokenContinuation.yield(Data([0xcc, 0xdd]))
    await Task.yield()
    let state = fixture.owner.snapshot()
    XCTAssertEqual(state["state"] as? String, "ended")
    XCTAssertEqual(state["update_token"] as? String, "")
  }

  func testWrongScopeAndLegacyAreEndedBeforeNewRequest() async throws {
    let fixture = Fixture()
    let legacy = FakeActivity(id: "legacy", scope: nil, startedAt: nil)
    fixture.backend.values = [legacy]
    _ = try await fixture.owner.prepare(scope: "scope-a")
    XCTAssertEqual(legacy.ends, 1)
    XCTAssertTrue(fixture.backend.cleanAtRequest)
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
  var foreground = true
  let backend = FakeBackend()
  let defaults = UserDefaults(suiteName: "otp-tests-\(UUID().uuidString)")!
  lazy var owner = OtpLiveActivity(backend: backend, defaults: defaults,
    now: { [unowned self] in self.now }, foreground: { [unowned self] in self.foreground })
}

@available(iOS 16.2, *)
@MainActor
private final class FakeBackend: OtpActivityBackend {
  var values: [FakeActivity] = []
  var requests = 0
  var cleanAtRequest = true
  var enabled: Bool { true }
  var activities: [any OtpActivityHandle] { values }
  func request(scope: String, startedAt: Date) throws -> any OtpActivityHandle {
    cleanAtRequest = values.allSatisfy { $0.status == .ended || $0.status == .dismissed }
    requests += 1
    let value = FakeActivity(id: "activity-\(requests)", scope: scope, startedAt: startedAt)
    values.append(value)
    return value
  }
}

@available(iOS 16.2, *)
@MainActor
private final class FakeActivity: OtpActivityHandle {
  let id: String
  let scope: String?
  let startedAt: Date?
  var status: ActivityState = .active
  var token: Data?
  var ends = 0
  let tokens: AsyncStream<Data>
  let states: AsyncStream<ActivityState>
  let tokenContinuation: AsyncStream<Data>.Continuation
  init(id: String, scope: String?, startedAt: Date?) {
    self.id = id; self.scope = scope; self.startedAt = startedAt
    var continuation: AsyncStream<Data>.Continuation!
    tokens = AsyncStream { continuation = $0 }
    tokenContinuation = continuation
    states = AsyncStream { _ in }
  }
  func end() async { ends += 1; status = .ended }
}
