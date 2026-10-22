import Flutter
import Foundation
import UIKit
import UserNotifications

final class APNsBridge: NSObject {
  static let channelName = "com.oneims.onewifi/apns"
  private static let pendingKey = "onewifi.apns.pending"

  private var channel: FlutterMethodChannel?
  private var deviceToken = ""
  private var pushToStartToken = ""
  private var registrationError = ""

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "APNs bridge unavailable", details: nil))
        return
      }
      switch call.method {
      case "register":
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
          result(self.tokenState())
        }
      case "state":
        result(self.tokenState())
      case "notificationState":
        self.notificationState(result: result)
      case "requestNotificationAuthorization":
        self.requestNotificationAuthorization(result: result)
      case "openNotificationSettings":
        DispatchQueue.main.async {
          self.openNotificationSettings()
          result(nil)
        }
      case "drain":
        result(self.drainPending())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didRegister(deviceToken: Data) {
    self.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    registrationError = ""
    emit(method: "token", arguments: tokenState())
  }

  func didFailToRegister(error: Error) {
    registrationError = error.localizedDescription
    emit(method: "registrationError", arguments: tokenState())
  }

  /// Live Activity 的 push-to-start 令牌与 alert 令牌是两个独立空间，
  /// 服务器必须分别保存。令牌变化后重新登记，否则服务器会继续发到旧令牌，
  /// 表现为锁屏再也收不到灵动岛。
  func didUpdateLiveActivityToken(_ token: String) {
    let normalized = token.lowercased()
    guard normalized != pushToStartToken else { return }
    pushToStartToken = normalized
    emit(method: "token", arguments: tokenState())
  }

  func receive(userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
    guard let event = parseEvent(userInfo) else {
      completion(.noData)
      return
    }
    guard UIApplication.shared.applicationState == .active else {
      // iOS already showed the remote alert. Record it so Flutter only acks
      // and does not post a second local notification after resume.
      appendPending(event.markedSystemPresented())
      completion(.newData)
      return
    }
    receiveForeground(userInfo: userInfo)
    completion(.newData)
  }

  func receiveForeground(userInfo: [AnyHashable: Any]) {
    guard let event = parseEvent(userInfo) else { return }
    // Both live and cached events only acknowledge the ordinary banner.
    appendPending(event.markedSystemPresented())
    emit(method: "notification", arguments: event.dictionary)
  }

  private func tokenState() -> [String: Any] {
    let environment = (Bundle.main.object(forInfoDictionaryKey: "OneWIFIApnEnvironment") as? String ?? "").lowercased()
    return [
      "device_token": deviceToken,
      "environment": environment == "sandbox" ? "sandbox" : "production",
      "registration_error": registrationError,
      "push_to_start_token": pushToStartToken,
    ]
  }

  private func notificationState(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      let authorization: String
      switch settings.authorizationStatus {
      case .authorized: authorization = "authorized"
      case .provisional: authorization = "provisional"
      case .ephemeral: authorization = "ephemeral"
      case .denied: authorization = "denied"
      case .notDetermined: authorization = "notDetermined"
      @unknown default: authorization = "unknown"
      }
      let alertsEnabled = settings.alertSetting == .enabled
      DispatchQueue.main.async {
        var state = self?.tokenState() ?? [:]
        state["authorization"] = authorization
        state["alerts_enabled"] = alertsEnabled
        result(state)
      }
    }
  }

  private func requestNotificationAuthorization(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
        self?.notificationState(result: result)
      }
    }
  }

  private func openNotificationSettings() {
    let target: URL?
    if #available(iOS 16.0, *) {
      target = URL(string: UIApplication.openNotificationSettingsURLString)
    } else {
      target = URL(string: UIApplication.openSettingsURLString)
    }
    guard let target else { return }
    UIApplication.shared.open(target)
  }

  private func appendPending(_ event: APNsSMS) {
    var values = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
    values.removeAll { ($0["sms_id"] as? NSNumber)?.int64Value == event.smsID }
    values.append(event.dictionary)
    UserDefaults.standard.set(values, forKey: Self.pendingKey)
  }

  private func drainPending() -> [[String: Any]] {
    let values = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
    UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    return values
  }

  private func emit(method: String, arguments: Any) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(method, arguments: arguments)
    }
  }

  private func parseEvent(_ userInfo: [AnyHashable: Any]) -> APNsSMS? {
    guard let smsID = (userInfo["sms_id"] as? NSNumber)?.int64Value,
          smsID > 0,
          let content = userInfo["content"] as? String,
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return APNsSMS(
      smsID: smsID,
      content: content,
      number: userInfo["number"] as? String ?? "",
      deviceLabel: userInfo["device_label"] as? String ?? ""
    )
  }
}

private struct APNsSMS {
  let smsID: Int64
  let content: String
  let number: String
  let deviceLabel: String
  let systemPresented: Bool

  init(
    smsID: Int64,
    content: String,
    number: String,
    deviceLabel: String,
    systemPresented: Bool = false
  ) {
    self.smsID = smsID
    self.content = content
    self.number = number
    self.deviceLabel = deviceLabel
    self.systemPresented = systemPresented
  }

  var dictionary: [String: Any] {
    [
      "sms_id": smsID,
      "content": content,
      "number": number,
      "device_label": deviceLabel,
      "system_presented": systemPresented,
    ]
  }

  func markedSystemPresented() -> APNsSMS {
    APNsSMS(
      smsID: smsID,
      content: content,
      number: number,
      deviceLabel: deviceLabel,
      systemPresented: true
    )
  }
}
