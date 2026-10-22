import XCTest
@testable import Runner

final class CallCoordinatorTests: XCTestCase {
  func testRefreshPreservesOwnerMediaGenerationAndOriginalOfflineDeadline() throws {
    let f = try Fixture(); let uuid = try f.answerWithMedia()
    f.platform.onAudio?(true)
    let generation = f.coordinator.snapshot["generation"] as? Int
    f.gateway.eventFailure = "call_events_server_error"
    f.gateway.onEventStatus?("offline")
    let deadline = try XCTUnwrap(f.scheduled.last(where: { $0.0 == 20 })?.1)
    XCTAssertEqual(f.coordinator.snapshot["eventError"] as? String, "call_events_server_error")
    let starts = f.gateway.starts
    f.command("refreshEvents", [:]); f.command("refreshEvents", [:])
    XCTAssertEqual(f.gateway.starts, starts + 1)
    XCTAssertEqual(f.coordinator.snapshot["generation"] as? Int, generation)
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["uuid"] as? String, uuid.uuidString)
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["owned"] as? Bool, true)
    XCTAssertEqual(f.mediaStarts, 1); XCTAssertEqual(f.media.stops, 0)
    XCTAssertEqual(f.gateway.actions, ["answer"])
    XCTAssertEqual(f.coordinator.snapshot["eventError"] as? String, "")
    XCTAssertFalse(deadline.isCancelled)
    XCTAssertEqual(f.scheduled.filter { $0.0 == 20 }.count, 1)
    deadline.perform()
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testRefreshRejectsOldGenerationBackgroundAuthorizationAndHistoryLimit() throws {
    let f = try Fixture()
    func rejected(_ generation: Int, _ code: String) {
      var failure: String?
      f.coordinator.command("refreshEvents", arguments: ["generation": generation]) {
        if case .failure(let error) = $0 { failure = callFailureCode(error) }
      }
      XCTAssertEqual(failure, code)
    }
    let generation = try XCTUnwrap(f.coordinator.snapshot["generation"] as? Int)
    rejected(generation - 1, "call_cancelled")
    f.coordinator.setForeground(false); rejected(generation, "call_state_conflict")
    f.coordinator.setForeground(true)
    let ended = try (0...8192).map { index in
      try GatewayCall(deviceID: "d", json: ["id": "c\(index)", "number": "", "direction": "incoming", "state": "ended"])
    }
    f.gateway.onSnapshot?([GatewayCallDevice(id: "d", label: "SIM", ready: true, calls: ended)])
    let starts = f.gateway.starts
    rejected(generation, "call_state_conflict")
    XCTAssertEqual(f.gateway.starts, starts)
    f.gateway.onEventStatus?("unauthorized"); rejected(generation, "call_cancelled")
  }

  func testConnectedRefreshIsNoOpAndNewSnapshotClearsOnlyEventDiagnostic() throws {
    let f = try Fixture(); f.emptyEvents()
    let starts = f.gateway.starts; let stops = f.gateway.stops
    f.command("refreshEvents", [:])
    XCTAssertEqual(f.gateway.starts, starts); XCTAssertEqual(f.gateway.stops, stops)
    f.gateway.eventFailure = "call_protocol_violation"; f.gateway.onEventStatus?("failed")
    XCTAssertEqual(f.coordinator.snapshot["eventError"] as? String, "call_protocol_violation")
    f.emptyEvents()
    XCTAssertEqual(f.coordinator.snapshot["eventError"] as? String, "")
  }

  func testRemoteActiveNeverAcquiresMedia() throws {
    let f = try Fixture()
    f.events(state: "active")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.mediaStarts, 0)
  }

  func testAnswerRequiresHTTPThenSystemActivationBeforeCapture() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    let action = CallSystemAction(uuid: uuid, kind: .answer) { _ in }
    f.platform.onAction?(action)
    XCTAssertEqual(f.gateway.actions, ["answer"])
    XCTAssertEqual(f.mediaStarts, 0)
    f.gateway.reply?(.success(f.json(state: "active")))
    XCTAssertEqual(f.mediaStarts, 1)
    XCTAssertFalse(f.media.capture)
    f.platform.onAudio?(true)
    XCTAssertTrue(f.media.capture)
    f.platform.onAudio?(false)
    XCTAssertFalse(f.media.capture)
  }

  func testDuplicateAnswerAndLateReplyAfterClearCannotReviveCall() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    var settled: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { settled.append($0) })
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { settled.append($0) })
    XCTAssertEqual(f.gateway.actions, ["answer"])
    let reply = f.gateway.reply
    f.coordinator.clear()
    reply?(.success(f.json(state: "active")))
    XCTAssertEqual(settled, [false, false])
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testMediaDiagnosticSurvivesHangupAndClearsWithConfiguration() throws {
    let f = try Fixture()
    _ = try f.answerWithMedia()
    f.media.diagnostic = "AUDIO-D1 txQueued=19 txDropped=4 rxQueued=0 rxDropped=0"
    let failure = try XCTUnwrap(f.media.onFailure)
    failure("call_audio_send_stalled")
    XCTAssertEqual(f.coordinator.snapshot["audioDiagnostic"] as? String, f.media.diagnostic)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_audio_send_stalled")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
    f.coordinator.clear()
    failure("call_audio_playback_stalled")
    XCTAssertEqual(f.coordinator.snapshot["audioDiagnostic"] as? String, "")
  }

  func testMediaUnauthorizedBeforeAudioActivationInvalidatesSession() throws {
    try assertMediaUnauthorizedInvalidatesSession(audioActive: false)
  }

  func testMediaUnauthorizedAfterAudioActivationInvalidatesSession() throws {
    try assertMediaUnauthorizedInvalidatesSession(audioActive: true)
  }

  private func assertMediaUnauthorizedInvalidatesSession(audioActive: Bool) throws {
    let f = try Fixture()
    let uuid = try f.answerWithMedia()
    f.platform.onAudio?(audioActive)
    XCTAssertEqual(f.media.capture, audioActive)
    XCTAssertEqual(f.media.systemActive, audioActive)
    XCTAssertEqual(f.coordinator.snapshot["eventStatus"] as? String, "connected")
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, true)
    let generation = try XCTUnwrap(f.coordinator.snapshot["generation"] as? Int)
    let staleFailure = try XCTUnwrap(f.media.onFailure)
    let staleChange = try XCTUnwrap(f.media.onChange)
    let staleSnapshot = try XCTUnwrap(f.gateway.onSnapshot)
    let staleStatus = try XCTUnwrap(f.gateway.onEventStatus)

    staleFailure("call_unauthorized")

    XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["eventStatus"] as? String, "unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["generation"] as? Int, generation + 1)
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, false)
    XCTAssertTrue((f.coordinator.snapshot["devices"] as? [[String: Any]])?.isEmpty == true)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.gateway.invalidations, 1)
    XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
    XCTAssertEqual(f.platform.ended, [uuid])
    XCTAssertEqual(f.media.stops, 1)
    XCTAssertFalse(f.media.capture)
    XCTAssertFalse(f.media.systemActive)

    let revision = f.coordinator.snapshot["revision"] as? Int
    let ringing = try GatewayCall(deviceID: "d", json: f.json(state: "ringing"))
    staleSnapshot([GatewayCallDevice(id: "d", label: "SIM", ready: true, calls: [ringing])])
    staleStatus("connected")
    staleChange()
    staleFailure("call_unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["revision"] as? Int, revision)
    XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["eventStatus"] as? String, "unauthorized")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.platform.incoming, [uuid])
    XCTAssertEqual(f.mediaStarts, 1)
    XCTAssertEqual(f.gateway.invalidations, 1)
  }

  func testOldMediaCallbacksAfterClearCannotInvalidateReplacementSession() throws {
    let f = try Fixture()
    _ = try f.answerWithMedia()
    let staleFailure = try XCTUnwrap(f.media.onFailure)
    let staleChange = try XCTUnwrap(f.media.onChange)
    f.coordinator.clear()
    try f.coordinator.configure(["origin": "https://example.com", "token": "replacement"])
    f.events(state: "ringing")
    let replacement = try XCTUnwrap(f.coordinator.snapshot["local"] as? [String: Any])
    let generation = f.coordinator.snapshot["generation"] as? Int
    let revision = f.coordinator.snapshot["revision"] as? Int
    let invalidations = f.gateway.invalidations
    staleFailure("call_unauthorized")
    staleChange()
    XCTAssertEqual(f.coordinator.snapshot["generation"] as? Int, generation)
    XCTAssertEqual(f.coordinator.snapshot["revision"] as? Int, revision)
    XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "configured")
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, true)
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["uuid"] as? String, replacement["uuid"] as? String)
    XCTAssertEqual(f.gateway.invalidations, invalidations)
    XCTAssertEqual(f.mediaStarts, 1)
    XCTAssertFalse(f.media.capture)
  }

  func testNonAuthorizationMediaFailuresEndCallWithoutInvalidatingSession() throws {
    for code in ["call_transport", "call_media_busy"] {
      let f = try Fixture()
      let uuid = try f.answerWithMedia()
      f.platform.onAudio?(true)
      XCTAssertTrue(f.media.capture)
      let generation = f.coordinator.snapshot["generation"] as? Int
      let failure = try XCTUnwrap(f.media.onFailure)
      failure(code)
      XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "configured")
      XCTAssertEqual(f.coordinator.snapshot["eventStatus"] as? String, "connected")
      XCTAssertEqual(f.coordinator.snapshot["generation"] as? Int, generation)
      XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, true)
      XCTAssertEqual(f.coordinator.snapshot["error"] as? String, code)
      XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
      XCTAssertEqual(f.gateway.invalidations, 0)
      XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
      XCTAssertEqual(f.platform.ended, [uuid])
      XCTAssertEqual(f.media.stops, 1)
      XCTAssertFalse(f.media.capture)
      XCTAssertFalse(f.media.systemActive)
    }
  }

  func testTerminalHistoryCannotReportRingingAgain() throws {
    let f = try Fixture()
    f.events(state: "ended")
    f.events(state: "ringing")
    XCTAssertTrue(f.platform.incoming.isEmpty)
  }

  func testStaleGenerationCannotDial() throws {
    let f = try Fixture()
    f.events(state: "ended")
    var failed = false
    f.coordinator.command("dial", arguments: ["generation": -1, "deviceId": "d", "number": "123"]) {
      if case .failure = $0 { failed = true }
    }
    XCTAssertTrue(failed)
    XCTAssertTrue(f.gateway.actions.isEmpty)
    XCTAssertTrue(f.platform.requests.isEmpty)
  }

  func testPermissionDeniedDoesNotReportOrCaptureIncoming() throws {
    let f = try Fixture(permission: false)
    f.events(state: "ringing")
    f.platform.onAudio?(true)
    XCTAssertTrue(f.platform.incoming.isEmpty)
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, false)
  }

  func testUnknownAnswerResultFollowedByRemoteActiveDoesNotAcquireOwnership() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    var completions: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { completions.append($0) })
    f.gateway.reply?(.failure(CallGatewayFailure.transport))
    f.events(state: "active")
    XCTAssertEqual(completions, [false])
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.gateway.actions, ["answer"])
  }

  func testLateIncomingReportIsEndedAfterClear() throws {
    let f = try Fixture()
    f.platform.deferIncoming = true
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.coordinator.clear()
    let before = f.platform.ended.count
    f.platform.reportReply?(nil)
    XCTAssertEqual(f.platform.ended.count, before + 1)
    XCTAssertEqual(f.platform.ended.last, uuid)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testSystemTimeoutAbandonsSDKCompletionAndLateExplicitOwnerIsCompensated() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    var completions: [Bool] = []
    let action = CallSystemAction(uuid: uuid, kind: .answer) { completions.append($0) }
    f.platform.onAction?(action)
    let reply = f.gateway.reply
    f.platform.onTimeout?(action.identifier)
    reply?(.success(f.json(state: "active")))
    XCTAssertTrue(completions.isEmpty)
    XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
    XCTAssertEqual(f.mediaStarts, 0)
  }

  func testEndStopsCaptureBeforeBackendReplyAndClearSettlesEndOnce() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    f.gateway.reply?(.success(f.json(state: "active")))
    f.platform.onAudio?(true)
    XCTAssertTrue(f.media.capture)
    var completions: [Bool] = []
    let end = CallSystemAction(uuid: uuid, kind: .end) { completions.append($0) }
    f.platform.onAction?(end)
    XCTAssertFalse(f.media.capture)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertTrue(completions.isEmpty)
    let reply = f.gateway.reply
    f.coordinator.clear()
    reply?(.success([:]))
    XCTAssertEqual(completions, [false])
  }

  func testIdleBackgroundStopsEventsButOwnedCallRetainsMedia() throws {
    let idle = try Fixture()
    idle.coordinator.setForeground(false)
    XCTAssertGreaterThan(idle.gateway.stops, 0)
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    f.gateway.reply?(.success(f.json(state: "active")))
    f.platform.onAudio?(true)
    f.coordinator.setForeground(false)
    XCTAssertTrue(f.media.capture)
    XCTAssertEqual(f.gateway.stops, 0)
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, false)
    f.coordinator.setForeground(true)
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, true)
    XCTAssertTrue(f.media.capture)
  }

  func testOldStreamAfterReconfigureCannotReportIncoming() throws {
    let f = try Fixture()
    let staleSnapshot = f.gateway.onSnapshot
    try f.coordinator.configure(["origin": "https://example.com", "token": "replacement"])
    let call = try GatewayCall(deviceID: "d", json: f.json(state: "ringing"))
    staleSnapshot?([GatewayCallDevice(id: "d", label: "SIM", ready: true, calls: [call])])
    XCTAssertTrue(f.platform.incoming.isEmpty)
    XCTAssertEqual(f.coordinator.snapshot["canReceiveCalls"] as? Bool, false)
  }

  func testSystemDTMFCapabilityUpdatesOnlyAfterMediaMetadata() throws {
    let f = try Fixture()
    f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    XCTAssertTrue(f.platform.dtmfUpdates.isEmpty)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    f.gateway.reply?(.success(f.json(state: "active")))
    f.media.onChange?()
    f.media.onChange?()
    XCTAssertEqual(f.platform.dtmfUpdates, [true])
  }

  func testRepeatedDTMFFailurePublishesNewPendingWithoutPreviousError() throws {
    let f = try Fixture(); let uuid = try f.answerWithMedia()
    var errors: [String] = []
    var pending: [Bool] = []
    var completed: [Bool] = []
    f.coordinator.onSnapshot = { snapshot in
      guard let local = snapshot["local"] as? [String: Any] else { return }
      errors.append(local["error"] as? String ?? "missing")
      pending.append(local["actionPending"] as? Bool ?? false)
    }
    for _ in 0..<2 {
      f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .dtmf("1")) { completed.append($0) })
      XCTAssertEqual(errors.last, "")
      XCTAssertEqual(pending.last, true)
      f.gateway.reply?(.failure(CallGatewayFailure.transport))
      XCTAssertEqual(errors.last, "call_transport")
      XCTAssertEqual(pending.last, false)
    }
    XCTAssertEqual(errors, ["", "call_transport", "", "call_transport"])
    XCTAssertEqual(pending, [true, false, true, false])
    XCTAssertEqual(completed, [false, false])
    XCTAssertEqual(f.gateway.actions, ["answer", "dtmf", "dtmf"])
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testRepeatedSystemTransactionFailurePublishesNewPendingWithoutPreviousError() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.platform.requestError = CallGatewayFailure.unavailable
    var errors: [String] = []
    var pending: [Bool] = []
    var rejected = 0
    f.coordinator.onSnapshot = { snapshot in
      guard let local = snapshot["local"] as? [String: Any] else { return }
      errors.append(local["error"] as? String ?? "missing")
      pending.append(local["actionPending"] as? Bool ?? false)
    }
    for _ in 0..<2 {
      f.coordinator.command("answer", arguments: ["generation": f.coordinator.snapshot["generation"]!,
        "uuid": uuid.uuidString, "deviceId": "d", "id": "c"]) {
        if case .failure = $0 { rejected += 1 }
      }
    }
    XCTAssertEqual(errors, ["", "call_system_transaction", "", "call_system_transaction"])
    XCTAssertEqual(pending, [true, false, true, false])
    XCTAssertEqual(rejected, 2)
    XCTAssertEqual(f.platform.requests.count, 2)
    XCTAssertTrue(f.gateway.actions.isEmpty)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testSystemDiagnosticRetainsOnlyBoundedCodesAndFixedLabels() {
    let secret = "secret-phone-token-url"
    let leaf = NSError(domain: secret, code: 99, userInfo: [NSLocalizedDescriptionKey: secret])
    let underlying = NSError(domain: NSOSStatusErrorDomain, code: -50, userInfo: [NSUnderlyingErrorKey: leaf])
    let error = NSError(domain: "com.apple.CallKit.error.requesttransaction", code: 1,
      userInfo: [NSUnderlyingErrorKey: underlying, NSLocalizedDescriptionKey: secret, "number": secret])
    let diagnostic = CallSystemDiagnostic.describe(error, stage: .transaction, kind: .start(secret), backgroundModes: ["audio"])
    XCTAssertTrue(diagnostic.contains("CK-D1\nstage=transaction action=start"))
    XCTAssertTrue(diagnostic.contains("backgroundAudio=true backgroundVoIP=false"))
    XCTAssertTrue(diagnostic.contains("error domain=com.apple.CallKit.error.requesttransaction code=1"))
    XCTAssertTrue(diagnostic.contains("underlying1 domain=NSOSStatusErrorDomain code=-50"))
    XCTAssertTrue(diagnostic.contains("underlying2 domain=other code=99"))
    XCTAssertFalse(diagnostic.contains(secret))
    XCTAssertLessThan(diagnostic.count, 600)
    let wrapped = NSError(domain: NSCocoaErrorDomain, code: 2, userInfo: [NSUnderlyingErrorKey: error])
    let bounded = CallSystemDiagnostic.describe(wrapped, stage: .transaction, kind: .dtmf(secret))
    XCTAssertFalse(bounded.contains("code=99"))
    XCTAssertFalse(bounded.contains(secret))
  }

  func testDialRejectionKeepsDiagnosticAfterLocalCleanupAndFreshEvents() throws {
    let f = try Fixture(); f.emptyEvents()
    f.platform.requestError = NSError(domain: "com.apple.CallKit.error.requesttransaction", code: 2)
    var code: String?
    f.coordinator.command("dial", arguments: ["generation": f.coordinator.snapshot["generation"]!,
      "deviceId": "d", "number": "123"]) {
      if case .failure(let error) = $0 { code = callFailureCode(error) }
    }
    XCTAssertEqual(code, "call_system_transaction")
    XCTAssertTrue(f.gateway.actions.isEmpty)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    let diagnostic = try XCTUnwrap(f.coordinator.snapshot["systemDiagnostic"] as? String)
    XCTAssertTrue(diagnostic.contains("action=start"))
    XCTAssertTrue(diagnostic.contains("domain=com.apple.CallKit.error.requesttransaction code=2"))
    f.emptyEvents()
    XCTAssertEqual(f.coordinator.snapshot["systemDiagnostic"] as? String, diagnostic)
    f.coordinator.clear()
    XCTAssertEqual(f.coordinator.snapshot["systemDiagnostic"] as? String, "")
  }

  func testIncomingReportRejectionRetainsSystemDiagnosticWithoutAnswering() throws {
    let f = try Fixture(); f.platform.deferIncoming = true; f.events(state: "ringing")
    f.platform.reportReply?(NSError(domain: "com.apple.CallKit.error.incomingcall", code: 3))
    let diagnostic = try XCTUnwrap(f.coordinator.snapshot["systemDiagnostic"] as? String)
    XCTAssertTrue(diagnostic.contains("stage=incomingReport action=incoming"))
    XCTAssertTrue(diagnostic.contains("domain=com.apple.CallKit.error.incomingcall code=3"))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_incoming_report")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertTrue(f.gateway.actions.isEmpty)
  }

  func testAnsweringRemovedFromFullSnapshotCannotReviveAfterReply() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { results.append($0) })
    let reply = f.gateway.reply
    f.emptyEvents()
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    reply?(.success(f.json(state: "active")))
    XCTAssertEqual(results, [false]); XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
  }

  func testSSEActiveBeforeDialReplyIsNotReplacedByOldDialing() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    f.events(state: "active", direction: "outgoing")
    var reply = f.json(state: "dialing", direction: "outgoing"); reply["media_ready"] = false
    f.gateway.reply?(.success(reply))
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["owned"] as? Bool, true)
    XCTAssertEqual(f.mediaStarts, 1)
    f.platform.onAudio?(true)
    XCTAssertTrue(f.media.capture); XCTAssertTrue(f.media.systemActive)
  }

  func testDialObservedThenRemovedBeforeHTTPReplyCannotRevive() throws {
    let f = try Fixture(); let uuid = f.dial()
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { results.append($0) })
    let reply = f.gateway.reply
    f.events(state: "active", direction: "outgoing"); f.emptyEvents()
    reply?(.success(f.json(state: "dialing", direction: "outgoing")))
    XCTAssertEqual(results, [false]); XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testProviderResetAbandonsPendingEndBeforeLateSuccess() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    f.gateway.reply?(.success(f.json(state: "active")))
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { results.append($0) })
    let reply = f.gateway.reply
    f.platform.onReset?()
    let error = f.coordinator.snapshot["error"] as? String
    reply?(.success([:]))
    XCTAssertTrue(results.isEmpty)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, error)
  }

  func testCancelBeforeSystemStartPreventsDialHTTP() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.command("hangup", ["deviceId": "d", "id": ""])
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { results.append($0) })
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    XCTAssertEqual(results, [false]); XCTAssertTrue(f.gateway.actions.isEmpty)
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testCancelledDispatchedDialStaysUnconfirmedUntilCompensatingHangupSucceeds() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let dialReply = try XCTUnwrap(f.gateway.reply)
    var ended: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { ended.append($0) })
    XCTAssertEqual(ended, [true])
    XCTAssertEqual(f.gateway.actions, ["dial"])
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_remote_end_unconfirmed")
    dialReply(.success(f.json(state: "active", direction: "outgoing")))
    XCTAssertEqual(f.gateway.actions, ["dial", "hangup"])
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_remote_end_unconfirmed")
    f.gateway.reply?(.success([:]))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertEqual(ended, [true])
  }

  func testCancelledDispatchedDialTransportFailureCannotConfirmRemoteEnd() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let reply = try XCTUnwrap(f.gateway.reply)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    reply(.failure(CallGatewayFailure.transport))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_remote_end_unconfirmed")
    XCTAssertEqual(f.gateway.actions, ["dial"])
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testCompensatingHangupFailureRetainsFailureWithoutAcquiringMedia() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let reply = try XCTUnwrap(f.gateway.reply)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    reply(.success(f.json(state: "active", direction: "outgoing")))
    f.gateway.reply?(.failure(CallGatewayFailure.transport))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_transport")
    XCTAssertEqual(f.mediaStarts, 0)
    XCTAssertEqual(f.gateway.actions, ["dial", "hangup"])
  }

  func testKnownTargetEndResultUpdatesOnlyItsOwnStatus() throws {
    for succeeds in [true, false] {
      let f = try Fixture(); f.events(state: "ringing")
      var ended: [Bool] = []
      f.platform.onAction?(CallSystemAction(uuid: f.platform.incoming[0], kind: .end) { ended.append($0) })
      XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_remote_end_unconfirmed")
      XCTAssertTrue(ended.isEmpty)
      f.gateway.reply?(succeeds ? .success([:]) : .failure(CallGatewayFailure.transport))
      XCTAssertEqual(ended, [succeeds])
      XCTAssertEqual(f.coordinator.snapshot["error"] as? String, succeeds ? "" : "call_transport")
      XCTAssertEqual(f.gateway.actions, ["hangup"])
    }
  }

  func testOldEndResultCannotOverwriteNewCallOrLaterEndStatus() throws {
    for succeeds in [true, false] {
      for endReplacement in [true, false] {
        let f = try Fixture(); f.events(state: "ringing")
        f.platform.onAction?(CallSystemAction(uuid: f.platform.incoming[0], kind: .end) { _ in })
        let oldEndReply = try XCTUnwrap(f.gateway.reply)
        let replacement = f.dial()
        XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
        if endReplacement {
          f.platform.onAction?(CallSystemAction(uuid: replacement, kind: .start("123")) { _ in })
          f.platform.onAction?(CallSystemAction(uuid: replacement, kind: .end) { _ in })
        }
        let expected = endReplacement ? "call_remote_end_unconfirmed" : ""
        oldEndReply(succeeds ? .success([:]) : .failure(CallGatewayFailure.transport))
        XCTAssertEqual(f.coordinator.snapshot["error"] as? String, expected)
        if !endReplacement {
          XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["uuid"] as? String, replacement.uuidString)
        }
      }
    }
  }

  func testOldCompensationResultCannotOverwriteLaterEndStatus() throws {
    for succeeds in [true, false] {
      let f = try Fixture(); let first = f.dial()
      f.platform.onAction?(CallSystemAction(uuid: first, kind: .start("123")) { _ in })
      let firstDialReply = try XCTUnwrap(f.gateway.reply)
      f.platform.onAction?(CallSystemAction(uuid: first, kind: .end) { _ in })
      firstDialReply(.success(f.json(state: "active", direction: "outgoing")))
      let compensationReply = try XCTUnwrap(f.gateway.reply)
      let next = f.dial()
      f.platform.onAction?(CallSystemAction(uuid: next, kind: .start("123")) { _ in })
      f.platform.onAction?(CallSystemAction(uuid: next, kind: .end) { _ in })
      compensationReply(succeeds ? .success([:]) : .failure(CallGatewayFailure.transport))
      XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_remote_end_unconfirmed")
      XCTAssertEqual(f.gateway.actions, ["dial", "hangup", "dial"])
      XCTAssertEqual(f.mediaStarts, 0)
    }
  }

  func testNewIncomingClearsOldEndStatusAndRejectsItsLateCompensation() throws {
    let f = try Fixture(); let first = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: first, kind: .start("123")) { _ in })
    let reply = try XCTUnwrap(f.gateway.reply)
    f.platform.onAction?(CallSystemAction(uuid: first, kind: .end) { _ in })
    f.events(state: "ringing")
    let incoming = try XCTUnwrap(f.platform.incoming.first)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
    var late = f.json(state: "active", direction: "outgoing"); late["id"] = "old"
    reply(.success(late))
    f.gateway.reply?(.failure(CallGatewayFailure.transport))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["uuid"] as? String, incoming.uuidString)
  }

  func testNewDialClearsPreviousCallFailure() throws {
    let f = try Fixture(); let first = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: first, kind: .start("123")) { _ in })
    f.gateway.reply?(.failure(CallGatewayFailure.transport))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_transport")
    _ = f.dial()
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testOldEndSuccessCannotClearLaterClaimFailure() throws {
    let f = try Fixture(); f.events(state: "ringing")
    f.platform.onAction?(CallSystemAction(uuid: f.platform.incoming[0], kind: .end) { _ in })
    let oldEndReply = try XCTUnwrap(f.gateway.reply)
    let next = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: next, kind: .start("123")) { _ in })
    f.gateway.reply?(.failure(CallGatewayFailure.transport))
    oldEndReply(.success([:]))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_transport")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testCompensationAfterClearCannotInvalidateNewSession() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let claimReply = try XCTUnwrap(f.gateway.reply)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    f.coordinator.clear()
    try f.coordinator.configure(["origin": "https://example.com", "token": "replacement"])
    let generation = f.coordinator.snapshot["generation"] as? Int
    claimReply(.success(f.json(state: "active", direction: "outgoing")))
    f.gateway.reply?(.failure(CallGatewayFailure.unauthorized))
    XCTAssertEqual(f.coordinator.snapshot["generation"] as? Int, generation)
    XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "configured")
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testEndUnauthorizedStillInvalidatesSameSessionAfterNewCall() throws {
    let f = try Fixture(); f.events(state: "ringing")
    f.platform.onAction?(CallSystemAction(uuid: f.platform.incoming[0], kind: .end) { _ in })
    let endReply = try XCTUnwrap(f.gateway.reply)
    _ = f.dial()
    endReply(.failure(CallGatewayFailure.unauthorized))
    XCTAssertEqual(f.coordinator.snapshot["status"] as? String, "unauthorized")
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_unauthorized")
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testResetRevokesLateCompensationStatusOwnership() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let claimReply = try XCTUnwrap(f.gateway.reply)
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    claimReply(.success(f.json(state: "active", direction: "outgoing")))
    let compensationReply = try XCTUnwrap(f.gateway.reply)
    f.platform.onReset?()
    compensationReply(.success([:]))
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "call_system_reset")
  }

  func testCompensationAcknowledgedBeforeSystemEndDoesNotLeavePendingStatus() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    let claimReply = try XCTUnwrap(f.gateway.reply)
    f.command("hangup", ["deviceId": "d", "id": ""])
    claimReply(.success(f.json(state: "active", direction: "outgoing")))
    f.gateway.reply?(.success([:]))
    var ended: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { ended.append($0) })
    XCTAssertEqual(ended, [true])
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
    XCTAssertEqual(f.gateway.actions, ["dial", "hangup"])
    XCTAssertEqual(f.mediaStarts, 0)
  }

  func testCancelBeforeSystemAnswerPreventsAnswerHTTP() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = try XCTUnwrap(f.platform.incoming.first)
    f.command("answer", ["deviceId": "d", "id": "c"])
    f.command("hangup", ["deviceId": "d", "id": "c"])
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { results.append($0) })
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    XCTAssertEqual(results, [false]); XCTAssertEqual(f.gateway.actions, ["hangup"])
  }

  func testCancelledClaimReplyThenSystemEndSendsOnlyOneHangup() throws {
    for direction in ["incoming", "outgoing"] {
      let f = try Fixture()
      let uuid: UUID
      let kind: CallSystemKind
      if direction == "incoming" { f.events(state: "ringing"); uuid = f.platform.incoming[0]; kind = .answer }
      else { uuid = f.dial(); kind = .start("123") }
      var results: [Bool] = []
      f.platform.onAction?(CallSystemAction(uuid: uuid, kind: kind) { results.append($0) })
      let reply = f.gateway.reply
      f.command("hangup", ["deviceId": "d", "id": direction == "incoming" ? "c" : ""])
      reply?(.success(f.json(state: "active", direction: direction)))
      f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
      XCTAssertEqual(results, [false]); XCTAssertEqual(f.gateway.actions.filter { $0 == "hangup" }.count, 1)
      XCTAssertEqual(f.mediaStarts, 0)
    }
  }

  func testSystemEndThenLateAnswerSendsOnlyOneHangup() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = f.platform.incoming[0]
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    let reply = f.gateway.reply
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .end) { _ in })
    reply?(.success(f.json(state: "active")))
    XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
    XCTAssertEqual(f.mediaStarts, 0)
  }

  func testLateAnswerWrongIDOrDirectionIsNeverCompensated() throws {
    for variant in ["id", "direction", "state"] {
      let f = try Fixture(); f.events(state: "ringing")
      let uuid = f.platform.incoming[0]
      let action = CallSystemAction(uuid: uuid, kind: .answer) { _ in }
      f.platform.onAction?(action); let reply = f.gateway.reply
      f.platform.onTimeout?(action.identifier)
      var response = f.json(state: "active")
      response[variant] = variant == "id" ? "other" : (variant == "direction" ? "outgoing" : "ringing")
      reply?(.success(response))
      XCTAssertEqual(f.gateway.actions, ["answer"]); XCTAssertEqual(f.mediaStarts, 0)
    }
  }

  func testLiveInvalidAnswerAndDialSuccessCannotOwnMedia() throws {
    for direction in ["incoming", "outgoing"] {
      let f = try Fixture()
      let uuid: UUID
      let kind: CallSystemKind
      if direction == "incoming" { f.events(state: "ringing"); uuid = f.platform.incoming[0]; kind = .answer }
      else { uuid = f.dial(); kind = .start("123") }
      f.platform.onAction?(CallSystemAction(uuid: uuid, kind: kind) { _ in })
      f.gateway.reply?(.success(f.json(state: "ringing", direction: direction)))
      XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any]); XCTAssertEqual(f.mediaStarts, 0)
    }
  }

  func testLocalWatchdogFailsLiveActionExactlyOnce() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = f.platform.incoming[0]
    var results: [Bool] = []
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { results.append($0) })
    let reply = f.gateway.reply
    f.fireLastTimer(seconds: 15)
    reply?(.success(f.json(state: "active")))
    XCTAssertEqual(results, [false]); XCTAssertEqual(f.mediaStarts, 0)
  }

  func testOfflineBudgetStopsOwnedCaptureAndEndsOnce() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = f.platform.incoming[0]
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    f.gateway.reply?(.success(f.json(state: "active"))); f.platform.onAudio?(true)
    f.gateway.onEventStatus?("offline")
    XCTAssertTrue(f.media.capture)
    f.fireLastTimer(seconds: 20)
    XCTAssertFalse(f.media.capture); XCTAssertEqual(f.gateway.actions, ["answer", "hangup"])
    XCTAssertNil(f.coordinator.snapshot["local"] as? [String: Any])
  }

  func testSystemStartContinuesWhenCallKitLeavesTheAppBackgrounded() throws {
    let f = try Fixture()
    f.coordinator.setForeground(false)
    let uuid = f.dial()
    var result: Bool?
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { result = $0 })
    XCTAssertEqual(f.gateway.actions, ["dial"])
    XCTAssertNil(result)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testEarlyMediaAllowsOnlyActivatedPlaybackUntilActiveSnapshot() throws {
    let f = try Fixture(); let uuid = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: uuid, kind: .start("123")) { _ in })
    f.gateway.reply?(.success(f.json(state: "early_media", direction: "outgoing")))
    XCTAssertFalse(f.media.systemActive); XCTAssertFalse(f.media.capture)
    f.platform.onAudio?(true)
    XCTAssertTrue(f.media.systemActive); XCTAssertFalse(f.media.capture)
    f.events(state: "active", direction: "outgoing")
    XCTAssertTrue(f.media.capture)
    f.platform.onAudio?(false)
    f.events(state: "active", direction: "outgoing")
    XCTAssertFalse(f.media.systemActive); XCTAssertFalse(f.media.capture)
  }

  func testSystemTimeoutDuringEndNeverCompletesExpiredSDKAction() throws {
    let f = try Fixture(); f.events(state: "ringing")
    let uuid = f.platform.incoming[0]
    var results: [Bool] = []
    let action = CallSystemAction(uuid: uuid, kind: .end) { results.append($0) }
    f.platform.onAction?(action); let reply = f.gateway.reply
    f.platform.onTimeout?(action.identifier)
    reply?(.success([:]))
    XCTAssertTrue(results.isEmpty)
    XCTAssertEqual(f.coordinator.snapshot["error"] as? String, "")
  }

  func testOldUUIDCannotCancelNewPendingCallWithSameGenerationAndEmptyID() throws {
    let f = try Fixture(); let old = f.dial()
    f.platform.onAction?(CallSystemAction(uuid: old, kind: .end) { _ in })
    let current = f.dial()
    var failure: String?
    let count = f.platform.requests.count
    f.coordinator.command("hangup", arguments: ["generation": f.coordinator.snapshot["generation"]!,
      "deviceId": "d", "id": "", "uuid": old.uuidString]) {
      if case .failure(let error) = $0 { failure = callFailureCode(error) }
    }
    XCTAssertEqual(failure, "call_state_conflict")
    XCTAssertEqual(f.platform.requests.count, count)
    XCTAssertEqual((f.coordinator.snapshot["local"] as? [String: Any])?["uuid"] as? String, current.uuidString)
  }

  func testEveryLocalCommandRejectsMissingUUIDBeforeSideEffects() throws {
    let f = try Fixture(); f.events(state: "ringing")
    for method in ["answer", "hangup", "mute", "route", "dtmf"] {
      var failure: String?
      f.coordinator.command(method, arguments: ["generation": f.coordinator.snapshot["generation"]!,
        "deviceId": "d", "id": "c", "muted": true, "endpoint": "speaker", "digit": "1"]) {
        if case .failure(let error) = $0 { failure = callFailureCode(error) }
      }
      XCTAssertEqual(failure, "call_state_conflict")
    }
    XCTAssertTrue(f.platform.requests.isEmpty); XCTAssertTrue(f.gateway.actions.isEmpty)
  }
}

private final class Fixture {
  let platform = TestCallPlatform()
  let gateway: TestCallGateway
  let media = TestCallMedia()
  var mediaStarts = 0
  var scheduled: [(TimeInterval, DispatchWorkItem)] = []
  var coordinator: CallKitCoordinator!
  init(permission: Bool = true) throws {
    gateway = TestCallGateway(configuration: try CallGatewayConfiguration(arguments: ["origin": "https://example.com", "token": "test"]))
    coordinator = CallKitCoordinator(platform: platform, gatewayFactory: { [gateway] _ in gateway }, mediaFactory: { [weak self] _, _ in
      self!.mediaStarts += 1
      return self!.media
    }, microphoneGranted: { permission }, requestMicrophone: { $0(permission) },
    schedule: { [weak self] delay, work in self?.scheduled.append((delay, work)) })
    try coordinator.configure(["origin": "https://example.com", "token": "test"])
  }
  func json(state: String, direction: String = "incoming") -> [String: Any] { ["id": "c", "number": "123", "direction": direction, "state": state, "media_ready": true] }
  func events(state: String, direction: String = "incoming") {
    let call = try! GatewayCall(deviceID: "d", json: json(state: state, direction: direction))
    gateway.onSnapshot?([GatewayCallDevice(id: "d", label: "SIM", ready: true, calls: [call])])
    gateway.onEventStatus?("connected")
  }
  func emptyEvents() { gateway.onSnapshot?([GatewayCallDevice(id: "d", label: "SIM", ready: true, calls: [])]) }
  func answerWithMedia() throws -> UUID {
    events(state: "ringing")
    let uuid = try XCTUnwrap(platform.incoming.first)
    platform.onAction?(CallSystemAction(uuid: uuid, kind: .answer) { _ in })
    gateway.reply?(.success(json(state: "active")))
    XCTAssertEqual(mediaStarts, 1)
    return uuid
  }
  func command(_ name: String, _ args: [String: Any]) {
    var args = args; args["generation"] = coordinator.snapshot["generation"]
    if args["uuid"] == nil { args["uuid"] = (coordinator.snapshot["local"] as? [String: Any])?["uuid"] }
    coordinator.command(name, arguments: args) { if case .failure(let error) = $0 { XCTFail("command rejected: \(error)") } }
  }
  func dial() -> UUID { emptyEvents(); command("dial", ["deviceId": "d", "number": "123"]); return platform.requestIDs.last! }
  func fireLastTimer(seconds: TimeInterval) {
    guard let work = scheduled.last(where: { $0.0 == seconds && !$0.1.isCancelled })?.1 else { XCTFail("missing timer"); return }
    work.perform()
  }
}

private final class TestCallPlatform: CallSystemProviding {
  var onAction: ((CallSystemAction) -> Void)?
  var onAudio: ((Bool) -> Void)?
  var onReset: (() -> Void)?
  var onTimeout: ((UUID) -> Void)?
  var incoming: [UUID] = []
  var ended: [UUID] = []
  var deferIncoming = false
  var reportReply: ((Error?) -> Void)?
  var requests: [CallSystemKind] = []
  var requestError: Error?
  var requestIDs: [UUID] = []
  var dtmfUpdates: [Bool] = []
  func request(uuid: UUID, kind: CallSystemKind, completion: @escaping (Error?) -> Void) { requests.append(kind); requestIDs.append(uuid); completion(requestError) }
  func reportIncoming(uuid: UUID, number: String, completion: @escaping (Error?) -> Void) {
    incoming.append(uuid)
    if deferIncoming { reportReply = completion } else { completion(nil) }
  }
  func reportEnded(uuid: UUID, reason: CallSystemEndReason) { ended.append(uuid) }
  func reportOutgoing(uuid: UUID, connected: Bool) {}
  func updateCapabilities(uuid: UUID, dtmfSupported: Bool) { dtmfUpdates.append(dtmfSupported) }
}

private final class TestCallGateway: CallGatewayServing {
  let configuration: CallGatewayConfiguration
  var onSnapshot: (([GatewayCallDevice]) -> Void)?
  var onEventStatus: ((String) -> Void)?
  var actions: [String] = []
  var stops = 0
  var starts = 0
  var eventFailure = ""
  private var eventsRunning = false
  var invalidations = 0
  var reply: ((Result<[String: Any], Error>) -> Void)?
  init(configuration: CallGatewayConfiguration) { self.configuration = configuration }
  func startEvents() {
    guard !eventsRunning else { return }; eventsRunning = true
    starts += 1; eventFailure = ""; onEventStatus?("connecting")
  }
  func stopEvents() { eventsRunning = false; stops += 1; eventFailure = ""; onEventStatus?("stopped") }
  func invalidate() { invalidations += 1 }
  func performAction(deviceID: String, action: String, body: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask? { actions.append(action); reply = completion; return nil }
  func mediaMetadata(deviceID: String, callID: String, completion: @escaping (Result<CallMediaDescription, Error>) -> Void) -> URLSessionDataTask? { nil }
  func makeMediaSocket(deviceID: String, callID: String) throws -> CallMediaSocket { throw CallGatewayFailure.unavailable }
}

private final class TestCallMedia: CallPCMTransporting {
  var onChange: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var diagnostic = ""
  var snapshot: [String: Any] { ["audioReady": false, "dtmfSupported": true, "audioDiagnostic": diagnostic] }
  var capture = false
  var systemActive = false
  var stops = 0
  func start() {}
  func setSystemAudioActive(_ active: Bool) { systemActive = active }
  func setCaptureEnabled(_ enabled: Bool) { capture = enabled }
  func setMuted(_ muted: Bool) {}
  func setRoute(_ endpoint: String) throws {}
  func stop() { stops += 1; capture = false; systemActive = false }
}
