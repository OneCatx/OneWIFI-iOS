import Flutter
import Foundation
import PushKit

/// PushKit 传输层。它只做两件事：拿 VoIP 令牌、把到达的 VoIP 推送交给
/// `CallKitCoordinator`。它不是通话所有者，也不判断这通电话该不该响——
/// 所有权和生命周期只由 coordinator 持有。
final class CallPushRegistry: NSObject, PKPushRegistryDelegate {
  static let channelName = "com.oneims.onewifi/call_push"

  private let coordinator: CallKitCoordinator
  private var registry: PKPushRegistry?
  private var channel: FlutterMethodChannel?
  private var token = ""

  init(coordinator: CallKitCoordinator) {
    self.coordinator = coordinator
    super.init()
  }

  /// 必须在 `didFinishLaunchingWithOptions` 里调用。
  ///
  /// 系统只把 VoIP 推送投给「进程里已经存在 PKPushRegistry(.voIP)」的应用；
  /// 被系统回收后由推送重新拉起时，Flutter 引擎往往还没启动。等 Flutter
  /// 发指令再建 registry 会让这次唤醒直接丢掉，所以这里由原生最先建立。
  func start() {
    if registry == nil {
      let registry = PKPushRegistry(queue: .main)
      registry.delegate = self
      registry.desiredPushTypes = [.voIP]
      self.registry = registry
    }
    takeToken(registry?.pushToken(for: .voIP))
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "PushKit bridge unavailable", details: nil))
        return
      }
      switch call.method {
      case "start":
        DispatchQueue.main.async {
          self.start()
          result(self.tokenState())
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    takeToken(credentials.token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    takeToken(nil)
  }

  /// 只要系统投了这条推送，就必须在回调返回前向 CallKit 报一次通话，
  /// 否则 iOS 会结束本进程。所以这里不做「要不要响」的判断：决策在
  /// coordinator 内完成，由它决定是振铃还是立刻结束。
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP,
          let call = PushCall(payload.dictionaryPayload) else {
      completion()
      return
    }
    DispatchQueue.main.async {
      self.coordinator.receivePush(
        deviceID: call.deviceID,
        callID: call.callID,
        label: call.deviceLabel,
        number: call.number
      ) { _ in
        // 上报结果不改变 PushKit 的契约：回调只表示这次唤醒处理完毕。
        DispatchQueue.main.async { completion() }
      }
    }
  }

  private func takeToken(_ data: Data?) {
    let next = data.map { value in value.map { String(format: "%02x", $0) }.joined() } ?? ""
    guard next != token else { return }
    token = next
    emitToken()
  }

  private func emitToken() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.channel?.invokeMethod("token", arguments: self.tokenState())
    }
  }

  /// 环境与短信链路共用 Info.plist 的 `APNS_ENVIRONMENT` 构建设置，避免两条
  /// APNs 链路各自声明环境后互相错位。
  private func tokenState() -> [String: Any] {
    let environment = (Bundle.main.object(forInfoDictionaryKey: "OneWIFIApnEnvironment") as? String ?? "").lowercased()
    return [
      "device_token": token,
      "environment": environment == "sandbox" ? "sandbox" : "production",
    ]
  }
}

/// 一条 VoIP 推送里唯一可信的部分是它自称的身份。字段缺失或不是本应用
/// 认识的来电事件时，宁可放弃这次唤醒，也不报一通没有依据的振铃。
private struct PushCall {
  let deviceID: String
  let callID: String
  let deviceLabel: String
  let number: String

  init?(_ payload: [AnyHashable: Any]) {
    guard payload["event"] as? String == "incoming_call",
          payload["direction"] as? String == "incoming" else {
      return nil
    }
    let deviceID = (payload["device_id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let callID = (payload["call_id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    guard !deviceID.isEmpty, !callID.isEmpty else { return nil }
    self.deviceID = deviceID
    self.callID = callID
    deviceLabel = (payload["device_label"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    number = (payload["number"] as? String ?? "").trimmingCharacters(in: .whitespaces)
  }
}