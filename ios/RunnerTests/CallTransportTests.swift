import XCTest
import AVFoundation
@testable import Runner

final class CallTransportTests: XCTestCase {
  func testTLSDiagnosticOnlyExposesBoundedCodesAndResets() {
    let secret = "secret-token-url"
    let underlying = NSError(domain: secret, code: 7, userInfo: [NSLocalizedDescriptionKey: secret])
    let error = NSError(domain: NSURLErrorDomain, code: -1200,
      userInfo: [NSUnderlyingErrorKey: underlying, NSURLErrorFailingURLStringErrorKey: secret])
    var diagnostic = CallTLSDiagnostic(pinConfigured: true)
    diagnostic.stage = "accepted"
    diagnostic.record(error)
    XCTAssertEqual(diagnostic.networkCodes, ["URL:-1200", "other:7"])
    XCTAssertTrue(diagnostic.summary.contains("pinConfigured=true sessionStage=accepted"))
    XCTAssertFalse(diagnostic.summary.contains(secret))
    let streamError = NSError(domain: "kCFErrorDomainCFNetwork", code: -1200, userInfo: [
      "_kCFStreamErrorDomainKey": 3, "_kCFStreamErrorCodeKey": -9802,
      NSLocalizedDescriptionKey: secret, NSURLErrorFailingURLStringErrorKey: secret,
    ])
    diagnostic.record(streamError)
    XCTAssertEqual(diagnostic.networkCodes, ["CFNetwork:-1200[streamDomain=3 streamCode=-9802]"])
    XCTAssertFalse(diagnostic.summary.contains(secret))
    let unsafeValues: [Any] = [secret, true, 1.5, 1_000_001]
    for unsafeValue in unsafeValues {
      diagnostic.record(NSError(domain: NSURLErrorDomain, code: -1200, userInfo: [
        "_kCFStreamErrorDomainKey": secret, "_kCFStreamErrorCodeKey": unsafeValue,
      ]))
      XCTAssertEqual(diagnostic.networkCodes, ["URL:-1200"])
      XCTAssertFalse(diagnostic.summary.contains(secret))
    }
    var nested = error
    for _ in 0..<10 { nested = NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSUnderlyingErrorKey: nested]) }
    diagnostic.record(nested)
    XCTAssertEqual(diagnostic.networkCodes.count, 4)
    diagnostic = CallTLSDiagnostic()
    XCTAssertTrue(diagnostic.networkCodes.isEmpty)
    XCTAssertEqual(diagnostic.stage, "no_challenge")
    XCTAssertFalse(diagnostic.pinConfigured)
  }

  func testHTTPRequiresExactPrivateAddressLiteral() throws {
    for host in ["10.0.0.1.attacker.example", "192.168.1.2.example.com", "10..0.0.1", "10.x.0.0.1", "+10.0.0.1", "10.0.0.-1", "010.0.0.1", "8.8.8.8", "[2001:4860:4860::8888]", "[fc00:not-an-ip]"] {
      XCTAssertThrowsError(try CallGatewayConfiguration(arguments: ["origin": "http://\(host)", "token": "test"]), host)
    }
    for host in ["10.0.0.1", "192.168.1.2", "172.16.0.1", "127.0.0.1", "[::1]", "[0:0:0:0:0:0:0:1]", "[fd00::1]", "[fe80::1]", "router.local"] {
      XCTAssertNoThrow(try CallGatewayConfiguration(arguments: ["origin": "http://\(host)", "token": "test"]), host)
    }
    XCTAssertNoThrow(try CallGatewayConfiguration(arguments: ["origin": "https://10.0.0.1.attacker.example", "token": "test"]))
  }

  func testConnectingStopDoesNotOpenRequest() {
    var opens = 0
    let stream = CallEventStream { opens += 1; throw CallGatewayFailure.transport }
    stream.onStatus = { status in if status == "connecting" { stream.stop() } }
    stream.start(); XCTAssertEqual(opens, 0); stream.onStatus = nil; stream.stop()
  }

  func testConnectingRestartOpensOnlyNewGeneration() {
    var opens = 0; var restarted = false
    let stream = CallEventStream { opens += 1; throw CallGatewayFailure.transport }
    stream.onStatus = { status in
      if status == "connecting", !restarted { restarted = true; stream.stop(); stream.start() }
    }
    stream.start(); XCTAssertEqual(opens, 1); stream.onStatus = nil; stream.stop()
  }

  func testTransportActivationAndEarlyMediaGatesActualCaptureAndSend() throws {
    let rig = try MediaRig(); rig.connect()
    rig.transport.setCaptureEnabled(true)
    rig.audio.emit(Data(repeating: 1, count: 320)); rig.clock.advance(0.02)
    XCTAssertEqual(rig.audio.starts, 0); XCTAssertTrue(rig.socket.sent.isEmpty)
    rig.transport.setCaptureEnabled(false)
    rig.transport.setSystemAudioActive(true)
    XCTAssertEqual(rig.audio.starts, 1); XCTAssertFalse(rig.audio.capturing)
    rig.socket.deliver(.success(.data(Data(repeating: 1, count: 320))))
    XCTAssertEqual(rig.audio.played.count, 1)
    rig.audio.emit(Data(repeating: 2, count: 320)); rig.clock.advance(0.02)
    XCTAssertTrue(rig.socket.sent.isEmpty)
    rig.transport.setCaptureEnabled(true)
    XCTAssertTrue(rig.audio.capturing)
    rig.audio.emit(Data(repeating: 3, count: 320)); rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent, [Data(repeating: 3, count: 320)])
    rig.transport.stop()
  }

  func testTransportMuteDropsQueuedAndPartialSpeechAndSendsSilence() throws {
    let rig = try MediaRig(); rig.activate()
    rig.audio.emit(Data(repeating: 7, count: 480))
    rig.transport.setMuted(true)
    XCTAssertFalse(rig.audio.capturing)
    rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent, [Data(repeating: 0, count: 320)])
    rig.socket.finishSend(nil); rig.transport.setMuted(false)
    rig.audio.emit(Data(repeating: 9, count: 160)); rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent.count, 1)
    rig.audio.emit(Data(repeating: 9, count: 160)); rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent.last, Data(repeating: 9, count: 320))
    rig.transport.stop()
  }

  func testTransportWSFailureClassificationIsIndependentOfCallbackOrder() throws {
    let cases: [(Int?, Int, String)] = [(409, NSURLErrorBadServerResponse, "call_media_busy"), (401, NSURLErrorBadServerResponse, "call_unauthorized"), (nil, NSURLErrorServerCertificateUntrusted, "call_trust")]
    for (status, errorCode, expected) in cases {
      for pingFirst in [true, false] {
        let rig = try MediaRig(); rig.transport.start(); rig.gateway.finishMetadata()
        if let status { rig.socket.response = HTTPURLResponse(url: URL(string: "https://gateway.example/media")!, statusCode: status, httpVersion: nil, headerFields: nil) }
        let error = NSError(domain: NSURLErrorDomain, code: errorCode)
        let receive = rig.socket.receiver; let ping = rig.socket.pinger
        if pingFirst { ping?(error); receive?(.failure(error)) }
        else { receive?(.failure(error)); ping?(error) }
        XCTAssertEqual(rig.failures, [expected]); XCTAssertEqual(rig.socket.cancels, 1)
        XCTAssertEqual(rig.socketFactoryCalls, 1); XCTAssertEqual(rig.gateway.actionCount, 0)
        XCTAssertFalse(rig.clock.hasTimer)
      }
    }
  }

  func testTransportStopRejectsLateMetadataAndSocketCallbacks() throws {
    let beforeMetadata = try MediaRig(); beforeMetadata.transport.start(); beforeMetadata.transport.stop()
    beforeMetadata.gateway.finishMetadata()
    XCTAssertEqual(beforeMetadata.socketFactoryCalls, 0); XCTAssertEqual(beforeMetadata.audio.starts, 0)
    let rig = try MediaRig(); rig.activate()
    rig.audio.emit(Data(repeating: 5, count: 320)); rig.clock.advance(0.02)
    let receive = rig.socket.receiver; let ping = rig.socket.pinger; let send = rig.socket.sender
    rig.transport.stop()
    receive?(.success(.data(Data(repeating: 1, count: 320)))); ping?(nil); send?(nil)
    rig.clock.advance(20)
    XCTAssertFalse(rig.transport.snapshot["audioReady"] as? Bool ?? true)
    XCTAssertEqual(rig.transport.snapshot["sentFrames"] as? Int, 0)
    XCTAssertEqual(rig.audio.starts, 1); XCTAssertEqual(rig.socket.cancels, 1)
    XCTAssertTrue(rig.failures.isEmpty)
  }

  func testTransportBurstShedsOldSpeechWithoutHangingUp() throws {
    let playback = try MediaRig(); playback.activate()
    playback.socket.deliver(.success(.data(Data(repeating: 1, count: 6400))))
    playback.socket.deliver(.success(.data(Data(repeating: 2, count: 1600))))
    XCTAssertEqual(playback.audio.played.count, 3)
    playback.socket.deliver(.success(.data(Data(repeating: 3, count: 320))))
    XCTAssertEqual(playback.transport.snapshot["playbackQueued"] as? Int, 25)
    XCTAssertEqual(playback.transport.snapshot["playbackDropped"] as? Int, 1)
    for _ in 0..<25 { playback.audio.finishPlay() }
    XCTAssertEqual(playback.audio.played.last, Data(repeating: 3, count: 320))
    XCTAssertEqual(playback.transport.snapshot["playbackQueued"] as? Int, 0)
    XCTAssertTrue(playback.failures.isEmpty); XCTAssertEqual(playback.socket.cancels, 0)
    playback.transport.stop()

    let capture = try MediaRig(); capture.activate()
    for byte in 0..<30 { capture.audio.emit(Data(repeating: UInt8(byte), count: 320)) }
    capture.clock.advance(0.02)
    XCTAssertEqual(capture.socket.sent.first, Data(repeating: 11, count: 320))
    for _ in 0..<19 { capture.socket.finishSend(nil) }
    XCTAssertEqual(capture.socket.sent.count, 19)
    XCTAssertEqual(capture.socket.sent.last, Data(repeating: 29, count: 320))
    XCTAssertEqual(capture.transport.snapshot["captureDropped"] as? Int, 11)
    XCTAssertTrue(capture.failures.isEmpty); XCTAssertTrue(capture.audio.capturing)
    capture.transport.stop()
  }

  func testDelayedTicksDrainWithoutAccumulatingDuringLongCall() throws {
    let rig = try MediaRig(); rig.activate()
    // Ten minutes: capture produces three frames while the UI timer only runs once per 60 ms.
    for _ in 0..<10_000 {
      rig.audio.emit(Data(repeating: 1, count: 960)); rig.clock.advance(0.06)
      for _ in 0..<3 { rig.socket.finishSend(nil) }
      rig.socket.pinger?(nil)
      XCTAssertEqual(rig.transport.snapshot["captureQueued"] as? Int, 0)
    }
    XCTAssertEqual(rig.transport.snapshot["sentFrames"] as? Int, 30_000)
    XCTAssertEqual(rig.transport.snapshot["captureDropped"] as? Int, 0)
    XCTAssertTrue(rig.failures.isEmpty); rig.transport.stop()
  }

  func testSendPauseRecoversButPersistentSendAndPlaybackStallsAreDistinct() throws {
    let rig = try MediaRig(); rig.activate()
    rig.audio.emit(Data(repeating: 1, count: 320)); rig.clock.advance(0.02)
    for _ in 0..<40 { rig.audio.emit(Data(repeating: 2, count: 320)); rig.clock.advance(0.02) }
    XCTAssertTrue(rig.failures.isEmpty)
    for _ in 0..<20 { rig.socket.finishSend(nil) }
    XCTAssertEqual(rig.transport.snapshot["captureQueued"] as? Int, 0)
    XCTAssertEqual(rig.transport.snapshot["captureDropped"] as? Int, 21)
    rig.transport.stop()

    let tx = try MediaRig(); tx.activate()
    tx.audio.emit(Data(repeating: 1, count: 320)); tx.clock.advance(0.02)
    tx.clock.advance(2.1); tx.clock.advance(3)
    XCTAssertEqual(tx.failures, ["call_audio_send_stalled"])
    XCTAssertEqual(tx.socket.cancels, 1)
    XCTAssertTrue((tx.transport.snapshot["audioDiagnostic"] as? String ?? "").hasPrefix("AUDIO-D1 txQueued="))
    let rx = try MediaRig(); rx.activate()
    rx.socket.deliver(.success(.data(Data(repeating: 1, count: 320))))
    rx.clock.advance(2.1)
    XCTAssertEqual(rx.failures, ["call_audio_playback_stalled"])
    XCTAssertEqual(rx.socket.cancels, 1)
  }

  func testPlaybackProgressResetsWatchdogAndInterruptionDropsQueuedSpeech() throws {
    let rig = try MediaRig(); rig.activate()
    rig.socket.deliver(.success(.data(Data(repeating: 1, count: 6400))))
    rig.clock.advance(1); rig.audio.finishPlay(); rig.clock.advance(1.1)
    XCTAssertTrue(rig.failures.isEmpty)
    let oldCompletion = rig.audio.playCompletions.first
    rig.audio.onInterruption?()
    XCTAssertEqual(rig.transport.snapshot["playbackQueued"] as? Int, 0)
    rig.transport.setSystemAudioActive(true)
    oldCompletion?(); rig.clock.advance(2.1)
    XCTAssertTrue(rig.failures.isEmpty); rig.transport.stop()
  }

  func testMuteDuringInflightSendCannotDrainOldSpeechOrFloodSilence() throws {
    let rig = try MediaRig(); rig.activate()
    rig.audio.emit(Data(repeating: 9, count: 960)); rig.clock.advance(0.02)
    rig.transport.setMuted(true); rig.socket.finishSend(nil)
    XCTAssertEqual(rig.socket.sent.count, 1)
    rig.clock.advance(0.02); rig.socket.finishSend(nil)
    XCTAssertEqual(rig.socket.sent.count, 2)
    XCTAssertEqual(rig.socket.sent.last, Data(repeating: 0, count: 320))
    rig.transport.setMuted(false); rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent.count, 2); rig.transport.stop()
  }

  func testTransportInterruptionRequiresNewActivationAndDropsOldCapture() throws {
    let rig = try MediaRig(); rig.activate()
    rig.audio.emit(Data(repeating: 4, count: 160))
    rig.audio.onInterruption?()
    XCTAssertFalse(rig.audio.capturing)
    rig.audio.emit(Data(repeating: 4, count: 160)); rig.clock.advance(0.02)
    XCTAssertTrue(rig.socket.sent.isEmpty)
    rig.transport.setSystemAudioActive(true)
    rig.audio.emit(Data(repeating: 6, count: 160)); rig.clock.advance(0.02)
    XCTAssertTrue(rig.socket.sent.isEmpty)
    rig.audio.emit(Data(repeating: 6, count: 160)); rig.clock.advance(0.02)
    XCTAssertEqual(rig.socket.sent, [Data(repeating: 6, count: 320)])
    rig.transport.stop()
  }

  func testTransportRouteRebuildIgnoresOldPlaybackCompletion() throws {
    let rig = try MediaRig(); rig.activate()
    rig.socket.deliver(.success(.data(Data(repeating: 0, count: 320))))
    let oldCompletion = rig.audio.playCompletions.first
    rig.audio.endpoint = "speaker"; rig.audio.onRouteChange?()
    XCTAssertEqual(rig.transport.snapshot["endpoint"] as? String, "speaker")
    XCTAssertEqual(rig.audio.starts, 2)
    rig.socket.deliver(.success(.data(Data(repeating: 0, count: 6400))))
    rig.socket.deliver(.success(.data(Data(repeating: 0, count: 1600))))
    oldCompletion?()
    rig.socket.deliver(.success(.data(Data(repeating: 0, count: 320))))
    XCTAssertTrue(rig.failures.isEmpty)
    XCTAssertEqual(rig.transport.snapshot["playbackQueued"] as? Int, 25)
    XCTAssertEqual(rig.transport.snapshot["playbackDropped"] as? Int, 1)
    rig.transport.stop()
  }

  func testTransportSendFailureAndHandshakeTimeoutUseSameStatusClassifier() throws {
    let sending = try MediaRig(); sending.activate()
    sending.audio.emit(Data(repeating: 1, count: 320)); sending.clock.advance(0.02)
    sending.socket.response = HTTPURLResponse(url: URL(string: "https://gateway.example/media")!, statusCode: 401, httpVersion: nil, headerFields: nil)
    sending.socket.finishSend(URLError(.networkConnectionLost))
    XCTAssertEqual(sending.failures, ["call_unauthorized"])
    let timeout = try MediaRig(); timeout.transport.start(); timeout.gateway.finishMetadata()
    timeout.socket.response = HTTPURLResponse(url: URL(string: "https://gateway.example/media")!, statusCode: 409, httpVersion: nil, headerFields: nil)
    timeout.clock.advance(9)
    XCTAssertEqual(timeout.failures, ["call_media_busy"]); XCTAssertFalse(timeout.clock.hasTimer)
  }

  func testTransportInvalidBinaryAndTextFramesStopWithoutPlayback() throws {
    for message in [URLSessionWebSocketTask.Message.data(Data([1])), .string("not PCM")] {
      let rig = try MediaRig(); rig.activate(); rig.socket.deliver(.success(message))
      XCTAssertEqual(rig.failures.count, 1); XCTAssertEqual(rig.socket.cancels, 1)
      XCTAssertTrue(rig.audio.played.isEmpty); XCTAssertFalse(rig.audio.capturing)
    }
  }

  func testTransportPermissionBoundaryFailureReleasesHardware() throws {
    let rig = try MediaRig(); rig.connect(); rig.audio.captureError = CallGatewayFailure.stateConflict
    rig.transport.setCaptureEnabled(true); rig.transport.setSystemAudioActive(true)
    XCTAssertEqual(rig.failures, ["call_audio_capture"])
    XCTAssertFalse(rig.audio.capturing); XCTAssertEqual(rig.socket.cancels, 1)
    XCTAssertFalse(rig.transport.snapshot["audioReady"] as? Bool ?? true)
  }

  func testActualAVAudioConverterProducesBounded160SampleFrames() throws {
    for rate in [8000.0, 16000.0, 24000.0, 44100.0, 48000.0] {
      let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
      let converter = try CallCaptureConverter(inputFormat: format)
      var frames = CallPCMFrames(); var count = 0
      for _ in 0..<30 {
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 0.02))!
        input.frameLength = input.frameCapacity
        for index in 0..<Int(input.frameLength) { input.floatChannelData![0][index] = 0.25 }
        try frames.appendCapture(converter.convert(input))
        while let frame = frames.popCapture() { XCTAssertEqual(frame.count, 320); XCTAssertNotEqual(frame, Data(repeating: 0, count: 320)); count += 1 }
      }
      XCTAssertGreaterThanOrEqual(count, 28); XCTAssertLessThanOrEqual(count, 30)
    }
  }

  func testCaptureResetDiscardsResamplerHistory() throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let converter = try CallCaptureConverter(inputFormat: format)
    let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960)!
    input.frameLength = 960
    for index in 0..<960 { input.floatChannelData![0][index] = 0.75 }
    _ = try converter.convert(input)
    converter.reset()
    for index in 0..<960 { input.floatChannelData![0][index] = 0 }
    let silence = try converter.convert(input)
    XCTAssertFalse(silence.isEmpty)
    XCTAssertEqual(silence, Data(repeating: 0, count: silence.count))
  }

  func testFirstInputFormatUnavailableRetriesThenStartsOnce() throws {
    let rig = try MediaRig(); rig.connect()
    rig.audio.startError = CallAudioFailure.inputUnavailable
    rig.transport.setSystemAudioActive(true)
    XCTAssertEqual(rig.audio.starts, 1)
    XCTAssertTrue(rig.failures.isEmpty)
    XCTAssertFalse(rig.transport.snapshot["audioReady"] as? Bool ?? true)
    for _ in 0..<4 { rig.clock.advance(0.02) }
    XCTAssertEqual(rig.audio.starts, 5)
    XCTAssertTrue(rig.failures.isEmpty)
    rig.audio.startError = nil
    rig.clock.advance(0.02)
    XCTAssertEqual(rig.audio.starts, 6)
    XCTAssertEqual(rig.transport.snapshot["audioReady"] as? Bool, true)
    XCTAssertEqual(rig.socket.cancels, 0)
    rig.transport.stop()
  }

  func testInputFormatUnavailableEventuallyFailsWithoutRestarting() throws {
    let rig = try MediaRig(); rig.connect()
    rig.audio.startError = CallAudioFailure.inputUnavailable
    rig.transport.setSystemAudioActive(true)
    for _ in 0..<24 { rig.clock.advance(0.02) }
    XCTAssertEqual(rig.failures, ["call_audio_input_unavailable"])
    XCTAssertEqual(rig.audio.starts, 25)
    XCTAssertEqual(rig.socket.cancels, 1)
    rig.clock.advance(1)
    XCTAssertEqual(rig.audio.starts, 25)
  }

  func testTransportPreservesTypedAudioFailuresAndStopsOnce() throws {
    for failure in [CallAudioFailure.permission, .inputFormat, .converterUnavailable] {
      let rig = try MediaRig(); rig.connect(); rig.audio.startError = failure
      rig.transport.setSystemAudioActive(true)
      XCTAssertEqual(rig.failures, [failure.rawValue])
      XCTAssertEqual(rig.socket.cancels, 1)
      XCTAssertFalse(rig.transport.snapshot["audioReady"] as? Bool ?? true)
    }
    let capture = try MediaRig(); capture.connect()
    capture.audio.captureError = CallAudioFailure.captureNotReady
    capture.transport.setCaptureEnabled(true); capture.transport.setSystemAudioActive(true)
    XCTAssertEqual(capture.failures, ["call_audio_capture_not_ready"])
    let conversion = try MediaRig(); conversion.activate()
    conversion.audio.onCapture?(.failure(CallAudioFailure.conversion))
    conversion.clock.advance(0.02)
    XCTAssertEqual(conversion.failures, ["call_audio_conversion"])
    XCTAssertTrue(conversion.socket.sent.isEmpty)
  }

  func testTransportDiscardsCaptureFailureWhileEarlyMediaOrMuted() throws {
    let rig = try MediaRig(); rig.connect(); rig.transport.setSystemAudioActive(true)
    rig.audio.onCapture?(.failure(CallAudioFailure.conversion)); rig.clock.advance(0.02)
    XCTAssertTrue(rig.failures.isEmpty); XCTAssertTrue(rig.socket.sent.isEmpty)
    rig.transport.setCaptureEnabled(true); rig.transport.setMuted(true)
    rig.audio.onCapture?(.failure(CallAudioFailure.conversion)); rig.clock.advance(0.02)
    XCTAssertTrue(rig.failures.isEmpty)
    XCTAssertEqual(rig.socket.sent, [Data(repeating: 0, count: 320)])
    rig.transport.stop()
  }

  func testRejectsPublicHTTPAndCredentialURLs() throws {
    for origin in ["http://example.com", "https://u:p@example.com", "https://example.com/path", "https://example.com?q=x"] {
      XCTAssertThrowsError(try CallGatewayConfiguration(arguments: ["origin": origin, "token": "test"]))
    }
    XCTAssertNoThrow(try CallGatewayConfiguration(arguments: ["origin": "http://192.168.1.2:8080", "token": "test"]))
    XCTAssertThrowsError(try CallGatewayConfiguration(arguments: ["origin": "https://example.com", "token": "a\r\nb"]))
    XCTAssertThrowsError(try CallGatewayConfiguration(arguments: ["origin": "https://example.com", "token": "test", "certificateFingerprint": "bad"]))
  }

  func testSSEChunkedUTF8BOMCRLFAndMultiline() throws {
    var parser = CallEventParser()
    let bytes = Data("\u{feff}: heartbeat\r\nevent: snapshot\r\nid: 1\r\ndata: 你\r\ndata: 好\r\n\r\n".utf8)
    var events: [CallServerEvent] = []
    for byte in bytes { events += try parser.append(Data([byte])) }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.data, "你\n好")
    XCTAssertEqual(events.first?.id, "1")
    XCTAssertTrue(try parser.append(Data("event: snapshot\ndata: truncated".utf8)).isEmpty)
  }

  func testSSERejectsOversizedAndInvalidUTF8() throws {
    var parser = CallEventParser(limit: 16)
    XCTAssertThrowsError(try parser.append(Data(repeating: 65, count: 17)))
    var invalid = CallEventParser()
    XCTAssertThrowsError(try invalid.append(Data([0xff, 10])))
  }

  func testSnapshotRejectsDuplicateIDsAndWrongBoolean() throws {
    let device: [String: Any] = ["device_id": "a", "label": "A", "ready": true, "calls": []]
    XCTAssertEqual(try CallSnapshotDecoder.decode(["devices": [device]]).count, 1)
    XCTAssertThrowsError(try CallSnapshotDecoder.decode(["devices": [device, device]]))
    XCTAssertThrowsError(try CallSnapshotDecoder.decode(["devices": [["device_id": "a", "label": "A", "ready": 1, "calls": []]]]))
  }

  func testPCMFramesAreBoundedAndMuteClearsPartialInput() throws {
    var queue = CallPCMFrames()
    try queue.appendCapture(Data(repeating: 1, count: 160))
    queue.setMuted(true)
    try queue.appendCapture(Data(repeating: 2, count: 320))
    XCTAssertEqual(queue.popCapture(), Data(repeating: 0, count: 320))
    XCTAssertNil(queue.popCapture())
    XCTAssertThrowsError(try queue.appendPlayback(Data([1])))
    XCTAssertThrowsError(try queue.appendPlayback(Data(repeating: 0, count: 6402)))
    try queue.appendPlayback(Data(repeating: 0, count: 6400))
    try queue.appendPlayback(Data(repeating: 2, count: 1920))
    XCTAssertEqual(queue.playbackCount, 22)
    XCTAssertEqual(queue.playbackDropped, 4)
  }

  func testCallMatchesGoOmittedFalseAndRejectsWrongType() throws {
    var row: [String: Any] = ["id": "1", "number": "123", "direction": "incoming", "state": "ringing"]
    XCTAssertFalse(try GatewayCall(deviceID: "d", json: row).mediaReady)
    row["media_ready"] = "false"
    XCTAssertThrowsError(try GatewayCall(deviceID: "d", json: row))
    row["media_ready"] = true; row["ended_at"] = "2026-01-01T00:00:00Z"
    XCTAssertTrue(try GatewayCall(deviceID: "d", json: row).isTerminal)
  }

  func testHTTPUnwrapsGatewayEnvelopeAndEncodesDeviceSegment() throws {
    let done = expectation(description: "gateway response")
    let config = try CallGatewayConfiguration(arguments: ["origin": "https://gateway.example", "token": "test-token"])
    let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [CallStubProtocol.self]
    CallStubProtocol.handle = { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertTrue(request.url!.absoluteString.contains("dev%2F%3F%23"))
      XCTAssertFalse(request.url!.absoluteString.contains("test-token"))
      return (202, Data("{\"data\":{\"id\":\"owned\"}}".utf8))
    }
    let client = CallGatewayClient(configuration: config, sessionConfiguration: session)
    client.performAction(deviceID: "dev/?#", action: "dial", body: ["number": "123"]) { result in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(try? result.get()["id"] as? String, "owned")
      done.fulfill()
    }
    wait(for: [done], timeout: 2); client.invalidate(); CallStubProtocol.handle = nil
  }

  func testMetadataRejectsForeignCallIDAndWrongFormat() throws {
    for payload in ["{\"data\":{\"id\":\"other\",\"codec\":\"PCMA\",\"format\":\"pcm_s16le_8000_mono\",\"dtmf\":true}}", "{\"data\":{\"id\":\"call\",\"codec\":\"PCMA\",\"format\":\"wrong\",\"dtmf\":true}}"] {
      let done = expectation(description: "reject metadata")
      let config = try CallGatewayConfiguration(arguments: ["origin": "https://gateway.example", "token": "test"])
      let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [CallStubProtocol.self]
      CallStubProtocol.handle = { _ in (200, Data(payload.utf8)) }
      let client = CallGatewayClient(configuration: config, sessionConfiguration: session)
      client.mediaMetadata(deviceID: "d", callID: "call") { result in
        if case .success = result { XCTFail("Invalid media metadata accepted") }; done.fulfill()
      }
      wait(for: [done], timeout: 2); client.invalidate()
    }
    CallStubProtocol.handle = nil
  }

  func testGatewayErrorCodesNeverExposeBackendMessage() {
    XCTAssertEqual(CallGatewayClient.httpFailure(409, object: ["error": ["code": "dtmf_unavailable", "message": "secret"]]).code, "dtmf_unavailable")
    XCTAssertEqual(CallGatewayClient.httpFailure(409, object: ["error": ["code": "call_media_busy"]]).code, "call_media_busy")
    XCTAssertEqual(callFailureCode(NSError(domain: "secret-token", code: 1)), "call_transport")
  }

  func testOutgoingQueueIsBoundedIncludingInflightSlot() throws {
    var queue = CallPCMFrames()
    for _ in 0..<19 { try queue.appendCapture(Data(repeating: 7, count: 320)) }
    try queue.appendCapture(Data(repeating: 9, count: 480))
    XCTAssertEqual(queue.captureCount, 19); XCTAssertEqual(queue.captureDropped, 1)
    for _ in 0..<18 { XCTAssertEqual(queue.popCapture(), Data(repeating: 7, count: 320)) }
    XCTAssertEqual(queue.popCapture(), Data(repeating: 9, count: 320))
    queue.setMuted(true); queue.setMuted(false)
    try queue.appendCapture(Data(repeating: 5, count: 160))
    XCTAssertNil(queue.popCapture())
    XCTAssertThrowsError(try queue.appendCapture(Data([1])))
  }

  func testCertificateValidityRejectsExpiredFutureAndMalformedDER() {
    func tlv(_ tag: UInt8, _ bytes: [UInt8]) -> [UInt8] { [tag, UInt8(bytes.count)] + bytes }
    func certificate(_ start: String, _ end: String) -> Data {
      let validity = tlv(0x30, tlv(0x17, Array(start.utf8)) + tlv(0x17, Array(end.utf8)))
      let tbs = tlv(0x30, tlv(2, [1]) + tlv(0x30, []) + tlv(0x30, []) + validity)
      return Data(tlv(0x30, tbs))
    }
    let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC
    XCTAssertTrue(CallCertificateValidity.containsNow(certificate("250101000000Z", "270101000000Z"), now: now))
    XCTAssertFalse(CallCertificateValidity.containsNow(certificate("230101000000Z", "240101000000Z"), now: now))
    XCTAssertFalse(CallCertificateValidity.containsNow(certificate("270101000000Z", "280101000000Z"), now: now))
    XCTAssertFalse(CallCertificateValidity.containsNow(Data([0x30, 0x84, 0xff])))
  }

  func testTransientEventHTTPRetriesOnceAndClearsDiagnosticOnSnapshot() throws {
    let configuration = try CallGatewayConfiguration(arguments: ["origin": "https://gateway.example", "token": "test"])
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CallStubProtocol.self]
    for status in [408, 429, 500, 503] {
      let done = expectation(description: "retry \(status)")
      var requests = 0
      CallStubProtocol.contentType = "text/event-stream"
      CallStubProtocol.handle = { _ in
        requests += 1
        return requests == 1 ? (status, Data()) : (200, Data("event: snapshot\nid: 1\ndata: {\"devices\":[]}\n\n".utf8))
      }
      let client = CallGatewayClient(configuration: configuration, sessionConfiguration: config)
      var offline = false
      client.onEventStatus = { state in if state == "offline" { offline = true; XCTAssertFalse(client.eventFailure.isEmpty) } }
      client.onSnapshot = { devices in
        XCTAssertTrue(devices.isEmpty); XCTAssertTrue(offline)
        XCTAssertEqual(requests, 2); XCTAssertEqual(client.eventFailure, "")
        client.stopEvents(); done.fulfill()
      }
      client.startEvents(); wait(for: [done], timeout: 8); client.invalidate()
    }
    CallStubProtocol.contentType = "application/json"; CallStubProtocol.handle = nil
  }

  func testPermanentEventFailuresDoNotRetryAndStopCancelsPendingRetry() {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CallStubProtocol.self]
    let session = URLSession(configuration: config)
    CallStubProtocol.handle = { _ in (200, Data()) }
    defer { session.invalidateAndCancel(); CallStubProtocol.handle = nil }
    for status in [401, 403, 204, 404, 501, 400, 200] {
      var opens = 0
      let stream = CallEventStream { opens += 1; return session.dataTask(with: URL(string: "https://gateway.example/events")!) }
      stream.start()
      XCTAssertFalse(stream.response(HTTPURLResponse(url: URL(string: "https://gateway.example/events")!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!))
      XCTAssertFalse(stream.failure.isEmpty)
      stream.complete(nil)
      let waited = expectation(description: "no retry")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { XCTAssertEqual(opens, 1); waited.fulfill() }
      wait(for: [waited], timeout: 2); stream.stop()
    }
    for code in [-1200, -1206, -1022] {
      let stream = CallEventStream { session.dataTask(with: URL(string: "https://gateway.example/events")!) }
      stream.start(); stream.complete(NSError(domain: NSURLErrorDomain, code: code))
      XCTAssertEqual(stream.failure, "call_trust"); stream.stop()
    }
    var opens = 0
    let stream = CallEventStream { opens += 1; return session.dataTask(with: URL(string: "https://gateway.example/events")!) }
    stream.onStatus = { if $0 == "offline" { stream.stop(); stream.start() } }
    stream.start()
    _ = stream.response(HTTPURLResponse(url: URL(string: "https://gateway.example/events")!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
    let waited = expectation(description: "old retry discarded")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { XCTAssertEqual(opens, 2); stream.stop(); waited.fulfill() }
    wait(for: [waited], timeout: 2)
  }

  func testStreamSequenceResetsOnRestartAndStoppedEventsCannotRevive() throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CallStubProtocol.self]
    // URLProtocol prevents network I/O; this test drives the parser/reducer, not URLSession delivery.
    let session = URLSession(configuration: config)
    let stream = CallEventStream { session.dataTask(with: URL(string: "https://gateway.example/events")!) }
    var snapshots = 0
    stream.onSnapshot = { _ in snapshots += 1 }
    CallStubProtocol.handle = { _ in (200, Data()) }
    func event(_ id: Int) -> Data { Data("event: snapshot\nid: \(id)\ndata: {\"devices\":[]}\n\n".utf8) }
    stream.start(); stream.receive(event(5)); stream.receive(event(4))
    XCTAssertEqual(snapshots, 1)
    stream.stop(); stream.receive(event(6)); XCTAssertEqual(snapshots, 1)
    stream.start(); stream.receive(event(1)); XCTAssertEqual(snapshots, 2)
    stream.stop(); session.invalidateAndCancel(); CallStubProtocol.handle = nil
  }

  func testStreamStatusCallbackStopPreventsSnapshotDelivery() {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CallStubProtocol.self]
    let session = URLSession(configuration: config)
    CallStubProtocol.handle = { _ in (200, Data()) }
    let stream = CallEventStream { session.dataTask(with: URL(string: "https://gateway.example/events")!) }
    var snapshots = 0
    stream.onSnapshot = { _ in snapshots += 1 }
    stream.onStatus = { status in if status == "connected" { stream.stop() } }
    stream.start(); stream.receive(Data("event: snapshot\nid: 1\ndata: {\"devices\":[]}\n\n".utf8))
    XCTAssertEqual(snapshots, 0)
    stream.onStatus = nil; stream.stop(); session.invalidateAndCancel(); CallStubProtocol.handle = nil
  }
}

private final class CallStubProtocol: URLProtocol {
  static var handle: ((URLRequest) -> (Int, Data))?
  static var contentType = "application/json"
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let handle = Self.handle else { client?.urlProtocol(self, didFailWithError: CallGatewayFailure.transport); return }
    let (status, data) = handle(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.contentType])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class MediaRig {
  let gateway: MediaGateway
  let socket = MediaSocket()
  let audio = MediaAudio()
  let clock = MediaClock()
  var transport: CallPCMTransport!
  var failures: [String] = []
  var socketFactoryCalls = 0
  init() throws {
    gateway = try MediaGateway()
    let call = try GatewayCall(deviceID: "d", json: ["id": "c", "number": "123", "state": "active", "direction": "outgoing"])
    transport = CallPCMTransport(gateway: gateway, call: call, audio: audio, clock: clock, socketFactory: { [unowned self] in self.socketFactoryCalls += 1; return self.socket })
    transport.onFailure = { [weak self] in self?.failures.append($0) }
  }
  func connect() { transport.start(); gateway.finishMetadata(); socket.pinger?(nil) }
  func activate() { connect(); transport.setCaptureEnabled(true); transport.setSystemAudioActive(true) }
}
private final class MediaGateway: CallGatewayServing {
  let configuration: CallGatewayConfiguration
  var onSnapshot: (([GatewayCallDevice]) -> Void)?
  var onEventStatus: ((String) -> Void)?
  var metadata: ((Result<CallMediaDescription, Error>) -> Void)?
  var actionCount = 0
  init() throws { configuration = try CallGatewayConfiguration(arguments: ["origin": "https://gateway.example", "token": "test"]) }
  func startEvents() {}
  func stopEvents() {}
  func invalidate() {}
  func performAction(deviceID: String, action: String, body: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask? { actionCount += 1; completion(.failure(CallGatewayFailure.invalidRequest)); return nil }
  func mediaMetadata(deviceID: String, callID: String, completion: @escaping (Result<CallMediaDescription, Error>) -> Void) -> URLSessionDataTask? { metadata = completion; return nil }
  func makeMediaSocket(deviceID: String, callID: String) throws -> URLSessionWebSocketTask { throw CallGatewayFailure.invalidRequest }
  func finishMetadata() { metadata?(.success(CallMediaDescription(id: "c", codec: "PCMA", format: "pcm_s16le_8000_mono", dtmfSupported: true))) }
}
private final class MediaSocket: CallMediaSocket {
  var response: URLResponse?
  var receiver: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
  var pinger: ((Error?) -> Void)?
  var sender: ((Error?) -> Void)?
  var sent: [Data] = []
  var cancels = 0
  func resume() {}
  func cancel() { cancels += 1 }
  func receive(_ completion: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) { receiver = completion }
  func ping(_ completion: @escaping (Error?) -> Void) { pinger = completion }
  func send(_ data: Data, completion: @escaping (Error?) -> Void) { sent.append(data); sender = completion }
  func deliver(_ result: Result<URLSessionWebSocketTask.Message, Error>) { let callback = receiver; receiver = nil; callback?(result) }
  func finishSend(_ error: Error?) { let callback = sender; sender = nil; callback?(error) }
}
private final class MediaAudio: CallAudioDevice {
  var onCapture: ((Result<Data, Error>) -> Void)?
  var onRouteChange: (() -> Void)?
  var onInterruption: (() -> Void)?
  var endpoint = "receiver"
  var endpoints: [[String: String]] { [["id": endpoint, "name": endpoint]] }
  var starts = 0; var capturing = false
  var captureError: Error?
  var startError: Error?
  var played: [Data] = []; var playCompletions: [() -> Void] = []
  func start() throws { starts += 1; if let startError { throw startError } }
  func stop() { capturing = false }
  func setCaptureEnabled(_ enabled: Bool) throws {
    if enabled, let captureError { throw captureError }; capturing = enabled
  }
  func setRoute(_ endpoint: String) throws { self.endpoint = endpoint }
  func play(_ data: Data, completion: @escaping () -> Void) throws { played.append(data); playCompletions.append(completion) }
  func finishPlay() { guard !playCompletions.isEmpty else { return }; playCompletions.removeFirst()() }
  func emit(_ data: Data) { onCapture?(.success(data)) } // Also exercise transport rejection of late hardware callbacks.
}
private final class MediaClock: CallMediaClock {
  var now = Date(timeIntervalSince1970: 1_700_000_000)
  var callback: (() -> Void)?
  var hasTimer: Bool { callback != nil }
  func schedule(_ interval: TimeInterval, _ callback: @escaping () -> Void) -> CallMediaCancellation {
    self.callback = callback
    return MediaCancellation { [weak self] in self?.callback = nil }
  }
  func advance(_ time: TimeInterval) { now = now.addingTimeInterval(time); callback?() }
}
private final class MediaCancellation: CallMediaCancellation {
  private let onCancel: () -> Void
  init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
  func cancel() { onCancel() }
}
