import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var otpBackgroundSeen = true
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.callCoordinator.setForeground(true)
    if otpBackgroundSeen, #available(iOS 16.2, *) {
      OtpLiveActivity.shared.foregroundEntry()
      otpBackgroundSeen = false
    }
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.callCoordinator.setForeground(false)
    otpBackgroundSeen = true
  }
}
