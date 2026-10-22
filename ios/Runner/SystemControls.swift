import Flutter
import UIKit

/// iOS 现成控件：SF Symbol、UISwitch、UIActivityIndicatorView。
final class SystemSymbol: NSObject, FlutterPlatformView {
  private let image = UIImageView()

  init(frame: CGRect, args: [String: Any]) {
    image.frame = frame
    image.contentMode = .scaleAspectFit
    image.tintColor = color(args["color"])
    let point = CGFloat(args["size"] as? Double ?? 20)
    let weight = UIImage.SymbolWeight(rawValue: args["weight"] as? Int ?? 4) ?? .regular
    let config = UIImage.SymbolConfiguration(pointSize: point, weight: weight)
    image.image = UIImage(systemName: args["name"] as? String ?? "circle", withConfiguration: config)
  }

  func view() -> UIView { image }
}

final class SystemSwitch: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let toggle = UISwitch()

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.oneims.onewifi/system_switch/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()
    toggle.frame = frame
    toggle.isOn = args["value"] as? Bool ?? false
    toggle.isEnabled = args["enabled"] as? Bool ?? true
    toggle.addTarget(self, action: #selector(changed), for: .valueChanged)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let next = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.toggle.setOn(next["value"] as? Bool ?? false, animated: false)
      self?.toggle.isEnabled = next["enabled"] as? Bool ?? true
      result(nil)
    }
  }

  func view() -> UIView { toggle }

  @objc private func changed() {
    channel.invokeMethod("changed", arguments: toggle.isOn)
  }
}

final class SystemSpinner: NSObject, FlutterPlatformView {
  private let spinner = UIActivityIndicatorView(style: .medium)

  init(frame: CGRect, args: [String: Any]) {
    spinner.frame = frame
    spinner.color = color(args["color"])
    spinner.startAnimating()
  }

  func view() -> UIView { spinner }
}

private func color(_ value: Any?) -> UIColor {
  let packed = value as? Int ?? 0xFF000000
  return UIColor(
    red: CGFloat((packed >> 16) & 0xFF) / 255,
    green: CGFloat((packed >> 8) & 0xFF) / 255,
    blue: CGFloat(packed & 0xFF) / 255,
    alpha: CGFloat((packed >> 24) & 0xFF) / 255
  )
}

final class SystemSymbolFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    SystemSymbol(frame: frame, args: args as? [String: Any] ?? [:])
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}

final class SystemSwitchFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    SystemSwitch(frame: frame, viewId: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}

final class SystemSpinnerFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    SystemSpinner(frame: frame, args: args as? [String: Any] ?? [:])
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}