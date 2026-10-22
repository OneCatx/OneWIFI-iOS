import Flutter
import UIKit

/// iOS 26 Liquid Glass。只给底栏和弹层，不给列表卡。
final class SystemGlassDock: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let bar = UITabBar()
  private let itemsBox = UIView()

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.oneims.onewifi/system_glass/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()
    itemsBox.frame = frame
    itemsBox.backgroundColor = .clear
    bar.frame = frame
    bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    bar.delegate = self
    apply(args)
    itemsBox.addSubview(bar)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let next = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.apply(next)
      result(nil)
    }
  }

  func view() -> UIView { itemsBox }

  private func apply(_ args: [String: Any]) {
    let labels = args["labels"] as? [String] ?? []
    let symbols = args["symbols"] as? [String] ?? []
    let selected = args["selected"] as? Int ?? 0
    bar.items = labels.enumerated().map { index, label in
      let symbol = index < symbols.count ? symbols[index] : "circle"
      let item = UITabBarItem(title: label, image: UIImage(systemName: symbol), tag: index)
      return item
    }
    if bar.items?.indices.contains(selected) == true {
      bar.selectedItem = bar.items?[selected]
    }
  }
}

extension SystemGlassDock: UITabBarDelegate {
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("select", arguments: item.tag)
  }
}

final class SystemGlassSurface: NSObject, FlutterPlatformView {
  private let box = UIVisualEffectView()

  init(frame: CGRect) {
    box.frame = frame
    box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if #available(iOS 26.0, *) {
      box.effect = UIGlassEffect(style: .regular)
    } else {
      box.effect = UIBlurEffect(style: .systemThinMaterial)
    }
    box.backgroundColor = .clear
  }

  func view() -> UIView { box }
}

final class SystemGlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    SystemGlassSurface(frame: frame)
  }
}

final class SystemGlassDockFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    SystemGlassDock(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}