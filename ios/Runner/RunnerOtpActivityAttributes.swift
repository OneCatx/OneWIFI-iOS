import ActivityKit
import Foundation

/// Runner App 专用 Live Activity 模型。与 OneWifiIsland 内同名逻辑各编各的，避免 target 循环。
struct OtpActivityAttributes: ActivityAttributes {
  public typealias ContentState = OtpActivityContentState

  var scopeID: String?
  var sessionStartedAt: Date?
  public init(scopeID: String? = nil, sessionStartedAt: Date? = nil) {
    self.scopeID = scopeID
    self.sessionStartedAt = sessionStartedAt
  }
}

struct OtpActivityContentState: Codable, Hashable {
  var code: String
  var sender: String
  var device: String
  var startedAt: Date
  func displayCode(isStale: Bool) -> String { isStale ? "" : code }

  public init(code: String, sender: String, device: String, startedAt: Date) {
    self.code = code
    self.sender = sender
    self.device = device
    self.startedAt = startedAt
  }
}
