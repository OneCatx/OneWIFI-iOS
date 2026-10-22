import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // One process-wide owner, independent of Flutter views and engine reattachment.
  let callCoordinator = CallKitCoordinator()
  private lazy var callSessionChannel = CallSessionChannel(coordinator: callCoordinator)
  private lazy var callPush = CallPushRegistry(coordinator: callCoordinator)
  private lazy var apnsBridge = APNsBridge()
  private lazy var otpNotifier = OtpNotifier { [weak self] userInfo in
    self?.apnsBridge.receiveForeground(userInfo: userInfo)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // VoIP 推送的注册必须早于 Flutter 引擎：被推送唤醒时系统要求进程里已经
    // 存在 PKPushRegistry(.voIP)，否则这次唤醒会丢失，来电不会响。
    callPush.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    apnsBridge.didRegister(deviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apnsBridge.didFailToRegister(error: error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    apnsBridge.receive(userInfo: userInfo, completion: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    callSessionChannel.register(messenger: messenger)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SystemGlass")!
    registrar.register(SystemGlassDockFactory(messenger: messenger), withId: "onewifi/system_glass_dock")
    registrar.register(SystemGlassSurfaceFactory(), withId: "onewifi/system_glass_surface")
    registrar.register(SystemSymbolFactory(), withId: "onewifi/system_symbol")
    registrar.register(SystemSwitchFactory(messenger: messenger), withId: "onewifi/system_switch")
    registrar.register(SystemSpinnerFactory(), withId: "onewifi/system_spinner")
    apnsBridge.register(messenger: messenger)
    otpNotifier.register(messenger: messenger)
    callPush.register(messenger: messenger)
  }

}
