import AVFoundation
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testAppDelegateOwnsCallCoordinator() throws {
    let delegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
    weak var coordinator = delegate.callCoordinator
    XCTAssertNotNil(coordinator)
    XCTAssertTrue(coordinator === delegate.callCoordinator)
  }

  func testPCMRejectsIncompleteSamplesAndPreservesCompleteSamples() {
    for count in [0, 1, 2, 3, 319, 320, 321] {
      let data = Data(repeating: 0x12, count: count)
      let buffer = CallAudioBridge.pcmBuffer(data)
      if count == 0 || count % 2 != 0 {
        XCTAssertNil(buffer, "Invalid byte count: \(count)")
      } else {
        XCTAssertEqual(Int(buffer!.frameLength), count / 2)
        let copied = Data(bytes: buffer!.int16ChannelData![0], count: count)
        XCTAssertEqual(copied, data)
      }
    }
  }

  func testStopCancelsPendingPermissionAndLateGrantDoesNotCompleteTwice() throws {
    var permissionReply: ((Bool) -> Void)?
    let bridge = CallAudioBridge(requestPermission: { permissionReply = $0 })
    var results: [Any?] = []
    bridge.start { results.append($0) }
    try bridge.stop()
    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")
    permissionReply?(true)
    let drained = expectation(description: "permission callback drained")
    DispatchQueue.main.async {
      XCTAssertEqual(results.count, 1)
      drained.fulfill()
    }
    wait(for: [drained], timeout: 1)
  }

  func testSecondPermissionAttemptWorksAfterCancellation() throws {
    var replies: [(Bool) -> Void] = []
    let bridge = CallAudioBridge(requestPermission: { replies.append($0) })
    var firstResults = 0
    bridge.start { _ in firstResults += 1 }
    try bridge.stop()
    let denied = expectation(description: "second request receives denial")
    bridge.start { result in
      XCTAssertEqual((result as? FlutterError)?.code, "mic_denied")
      denied.fulfill()
    }
    replies[0](true)
    replies[1](false)
    wait(for: [denied], timeout: 1)
    XCTAssertEqual(firstResults, 1)
    try bridge.stop()
  }

}
