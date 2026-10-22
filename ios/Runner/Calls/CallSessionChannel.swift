import Flutter
import Foundation
import UIKit

/// Session-scoped bridge; cancelling a Flutter event subscription does not end a call.
final class CallSessionChannel: NSObject, FlutterStreamHandler {
  private let coordinator: CallKitCoordinator
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var sink: FlutterEventSink?

  init(coordinator: CallKitCoordinator) {
    self.coordinator = coordinator
    super.init()
    coordinator.onSnapshot = { [weak self] snapshot in self?.sink?(snapshot) }
  }
  func register(messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: "com.oneims.onewifi/call_session", binaryMessenger: messenger)
    let events = FlutterEventChannel(name: "com.oneims.onewifi/call_session/events", binaryMessenger: messenger)
    methodChannel?.setMethodCallHandler(nil)
    eventChannel?.setStreamHandler(nil)
    methodChannel = method; eventChannel = events
    events.setStreamHandler(self)
    method.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "call_cancelled", message: nil, details: nil)); return }
      let arguments = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "configure": try self.coordinator.configure(arguments); result(nil)
        case "clear": self.coordinator.clear(); result(nil)
        case "snapshot": result(self.coordinator.snapshot)
        case "openAppSettings":
          guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(FlutterError(code: "call_settings_unavailable", message: nil, details: nil)); return
          }
          UIApplication.shared.open(url, options: [:]) { opened in
            result(opened ? nil : FlutterError(code: "call_settings_unavailable", message: nil, details: nil))
          }
        case "requestPermissions", "refreshEvents", "dial", "answer", "hangup", "mute", "route", "dtmf":
          self.coordinator.command(call.method, arguments: arguments) { response in
            switch response {
            case .success: result(nil)
            case .failure(let error): result(FlutterError(code: callFailureCode(error), message: nil, details: nil))
            }
          }
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: callFailureCode(error), message: nil, details: nil)) }
    }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events; events(coordinator.snapshot); return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
