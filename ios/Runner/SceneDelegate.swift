import Flutter
import UIKit

/// App lifecycle.
///
/// Exists to drive screen-capture protection: the cover view has to be shown
/// while the app is inactive, which is when iOS takes the app-switcher
/// snapshot.
class SceneDelegate: FlutterSceneDelegate {

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    // About to be snapshotted for the app switcher — cover the UI first.
    ScreenSecurityBridge.shared.setCoverVisible(true)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    ScreenSecurityBridge.shared.setCoverVisible(false)
  }
}
