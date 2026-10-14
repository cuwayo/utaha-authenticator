import Flutter
import UIKit

/// Blocks screen capture and hides the app in the app switcher.
///
/// Implements the same `moe.nanakura.utaha/screen_security` channel as the
/// Android side, so the Dart code needs no platform branch.
///
/// Two mechanisms are used, because they cover different things and have
/// different reliability:
///
/// 1. **App-switcher cover** — a blurred snapshot-blocking view is shown while
///    the app is inactive. This is documented behaviour and always works: it is
///    what stops the OS's task-switcher thumbnail from showing live codes.
///
/// 2. **Secure-field overlay** — a `UITextField` with `isSecureTextEntry` is
///    woven into the window's layer tree. iOS excludes anything inside a secure
///    text field from screenshots and screen recordings, and the whole window
///    ends up inside it. This is **undocumented and relies on a side effect** of
///    how UIKit renders secure input. It is best-effort: it works on current
///    iOS versions, and Apple has never guaranteed it.
///
/// The honest summary: mechanism 1 is reliable, mechanism 2 is a hack that
/// currently works. Neither protects against a jailbroken device or an OS-level
/// capture, and neither can be verified without a real device.
final class ScreenSecurity {
  static let channelName = "moe.nanakura.utaha/screen_security"

  private weak var window: UIWindow?
  private var secureField: UITextField?
  private var coverView: UIView?

  /// Set by `enable()` and cleared by `disable()`.
  private(set) var isEnabled = false

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "unavailable",
          message: "Screen security is no longer available.",
          details: nil
        ))
        return
      }
      switch call.method {
      case "enable":
        self.enable()
        result(true)
      case "disable":
        self.disable()
        result(false)
      case "isEnabled":
        result(self.isEnabled)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Applies the protections. Safe to call repeatedly.
  func enable() {
    guard !isEnabled else { return }
    isEnabled = true
    installSecureOverlay()
    installAppSwitcherCover()
  }

  /// Removes both protections.
  func disable() {
    isEnabled = false

    secureField?.removeFromSuperview()
    secureField = nil

    coverView?.removeFromSuperview()
    coverView = nil
  }

  /// Called by the scene delegate when the app becomes inactive or active.
  func setCoverVisible(_ visible: Bool) {
    guard isEnabled else { return }
    coverView?.isHidden = !visible
  }

  // MARK: - Secure-field overlay

  /// Weaves a secure text field into the window's layer tree.
  ///
  /// The trick is not merely adding the field as a subview: the window's own
  /// layer is reparented *into* the secure field's layer, so everything the
  /// window draws is rendered inside a secure container and is therefore
  /// excluded from capture. The field itself is transparent and 1x1.
  private func installSecureOverlay() {
    guard secureField == nil, let window = resolveWindow() else { return }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    // Transparent and out of the way: this is a rendering trick, not visible UI.
    field.backgroundColor = .clear
    field.tintColor = .clear
    field.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

    window.addSubview(field)

    // The reparenting that makes it effective. If either layer is missing —
    // which can happen if the window is not yet attached to a screen — the
    // overlay is simply not applied, and the app keeps working unprotected
    // rather than crashing.
    if let superlayer = window.layer.superlayer {
      superlayer.addSublayer(field.layer)
      field.layer.sublayers?.first?.addSublayer(window.layer)
      secureField = field
    } else {
      field.removeFromSuperview()
    }
  }

  // MARK: - App switcher cover

  /// Adds a blurred view that hides the UI while the app is not in front.
  private func installAppSwitcherCover() {
    guard coverView == nil, let window = resolveWindow() else { return }

    let cover = UIVisualEffectView(
      effect: UIBlurEffect(style: .systemThickMaterial)
    )
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.isHidden = true
    window.addSubview(cover)
    coverView = cover
  }

  // MARK: - Window resolution

  /// Finds the key window across both scene-based and legacy lifecycles.
  ///
  /// This app uses a `SceneDelegate` on current iOS but the older
  /// `UIApplication.windows` path on anything earlier, and the two need
  /// different lookups.
  private func resolveWindow() -> UIWindow? {
    if let window {
      return window
    }
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let window = scenes
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
      ?? scenes.flatMap(\.windows).first
      ?? UIApplication.shared.windows.first
    self.window = window
    return window
  }
}

/// A single process-wide instance.
///
/// `AppDelegate` registers the channel and `SceneDelegate` drives the cover, and
/// both must act on the *same* object — a second instance would install a second
/// cover and never hide the first.
enum ScreenSecurityBridge {
  static let shared = ScreenSecurity()
}
