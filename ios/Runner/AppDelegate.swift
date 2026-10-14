import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Screen-capture protection. The Android side sets FLAG_SECURE; iOS has no
    // equivalent, so this registers a channel of the same name and applies an
    // overlay instead. See ScreenSecurity.swift.
    // `messenger()` is non-optional in the Flutter iOS API, so there is nothing
    // to unwrap — an `if let` here is a compile error.
    ScreenSecurityBridge.shared.register(
      with: engineBridge.applicationRegistrar.messenger()
    )
  }
}
