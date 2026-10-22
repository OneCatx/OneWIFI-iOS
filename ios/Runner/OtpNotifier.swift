import Flutter
import UIKit
import UserNotifications

/// 前台验证码通知。只有系统确认已展示才回 true，拒绝授权不回 true。
final class OtpNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let channelName = "com.oneims.onewifi/otp"

  private var pending: [(Bool) -> Void] = []
  private var asked = false
  private let remoteNotification: ([AnyHashable: Any]) -> Void

  init(remoteNotification: @escaping ([AnyHashable: Any]) -> Void) {
    self.remoteNotification = remoteNotification
    super.init()
  }

  func register(messenger: FlutterBinaryMessenger) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: "ONEWIFI_SMS",
        actions: [
          UNNotificationAction(
            identifier: "COPY_CODE",
            title: "复制",
            options: []
          ),
        ],
        intentIdentifiers: [],
        options: []
      ),
    ])
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    if #available(iOS 16.2, *) {
      Task { @MainActor in
        OtpLiveActivity.shared.onState = { state in channel.invokeMethod("activityState", arguments: state) }
      }
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "show":
        let args = call.arguments as? [String: Any]
        let code = args?["code"] as? String ?? ""
        guard !code.isEmpty else {
          result(false)
          return
        }
        let sender = args?["sender"] as? String ?? ""
        let device = args?["device"] as? String ?? ""
        self.show(code: code, sender: sender, device: device, result: result)
      case "showMessage":
        let args = call.arguments as? [String: Any]
        let text = args?["content"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(false)
          return
        }
        let sender = args?["sender"] as? String ?? ""
        let device = args?["device"] as? String ?? ""
        self.presentRemote(content: text, sender: sender, device: device, completion: result)
      case "scopeIdentifier", "prepareActivity", "activityState", "endActivity", "pendingActivityEnds", "acknowledgeActivityEnd":
        let args = call.arguments as? [String: Any]
        Task { @MainActor in
          guard #available(iOS 16.2, *) else {
            result(FlutterError(code: "activity_unavailable", message: "系统不支持实时活动。", details: nil))
            return
          }
          do {
            let owner = OtpLiveActivity.shared
            switch call.method {
            case "scopeIdentifier": result(owner.scopeIdentifier(key: args?["scope_key"] as? String ?? ""))
            case "prepareActivity": result(try await owner.prepare(scope: args?["scope_id"] as? String ?? ""))
            case "endActivity": result(await owner.end(scope: args?["scope_id"] as? String ?? ""))
            case "pendingActivityEnds": result(owner.pendingEnds(scope: args?["scope_id"] as? String ?? ""))
            case "acknowledgeActivityEnd":
              owner.acknowledgeEnd(scope: args?["scope_id"] as? String ?? "", id: args?["activity_id"] as? String ?? "", revision: args?["revision"] as? Int ?? 0)
              result(nil)
            default: result(owner.snapshot())
            }
          } catch {
            result(FlutterError(code: "activity_failed", message: error.localizedDescription, details: nil))
          }
        }
      case "showActivity":
        // Legacy callers cannot create or write a receive-only session.
        result(false)
      case "cancel":
        DispatchQueue.main.async {
          self.pending.forEach { $0(false) }
          self.pending.removeAll()
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["onewifi.otp"])
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["onewifi.otp"])
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func show(code: String, sender: String, device: String, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          self.post(code: code, sender: sender, device: device, result: result)
        case .notDetermined:
          self.ask(code: code, sender: sender, device: device, result: result)
        default:
          result(false)
        }
      }
    }
  }

  private func ask(code: String, sender: String, device: String, result: @escaping FlutterResult) {
    pending.append { granted in
      if granted {
        self.post(code: code, sender: sender, device: device, result: result)
      } else {
        result(false)
      }
    }
    guard !asked else { return }
    asked = true
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async {
        let waiting = self.pending
        self.pending.removeAll()
        self.asked = false
        waiting.forEach { $0(granted) }
      }
    }
  }

  func presentRemote(content text: String, sender: String, device: String, completion: @escaping (Bool) -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        self.postRemote(content: text, sender: sender, device: device, completion: completion)
      default:
        completion(false)
      }
    }
  }

  private func post(code: String, sender: String, device: String, result: @escaping FlutterResult) {
    postNotification(
      title: "验证码 \(code)",
      subtitle: "来自 \(visibleName(sender.isEmpty ? device : sender)) · 点击复制",
      body: code,
      category: "ONEWIFI_SMS",
      userInfo: ["code": code],
      identifier: "onewifi.otp",
      completion: result
    )
  }

  private func postRemote(content text: String, sender: String, device: String, completion: @escaping (Bool) -> Void) {
    postNotification(
      title: "短信",
      subtitle: "",
      body: text,
      category: "ONEWIFI_SMS",
      userInfo: [:],
      identifier: "onewifi.apns.\(UUID().uuidString)",
      completion: completion
    )
  }

  private func visibleName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "短信" : trimmed
  }

  private func postNotification(
    title: String,
    subtitle: String,
    body: String,
    category: String,
    userInfo: [AnyHashable: Any],
    identifier: String,
    completion: @escaping (Bool) -> Void
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = body
    content.categoryIdentifier = category
    content.userInfo = userInfo
    content.sound = .default
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        completion(error == nil)
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Local notifications must not loop back into the APNs ingestion path.
    if notification.request.trigger is UNPushNotificationTrigger {
      let info = notification.request.content.userInfo
      DispatchQueue.main.async { self.remoteNotification(info) }
    }
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let code = (info["code"] as? String) ?? response.notification.request.content.body
    if response.actionIdentifier == "COPY_CODE" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      UIPasteboard.general.string = code
    }
    completionHandler()
  }
}
