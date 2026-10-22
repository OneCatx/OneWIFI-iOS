import ActivityKit
import Foundation

/// App 与 Widget Extension 共用的 Live Activity 属性。
/// 请将本文件同时加入 Runner 与 OneWifiIsland 两个 target。
struct OtpActivityAttributes: ActivityAttributes {
  public typealias ContentState = OtpActivityContentState

  public init() {}
}

struct OtpActivityContentState: Codable, Hashable {
  var code: String
  var sender: String
  var device: String
  var startedAt: Date

  public init(code: String, sender: String, device: String, startedAt: Date) {
    self.code = code
    self.sender = sender
    self.device = device
    self.startedAt = startedAt
  }
}
