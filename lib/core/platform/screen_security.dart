import 'package:flutter/services.dart';

/// Controls whether the OS is allowed to capture this app's screen.
///
/// Two things depend on this: screenshots and screen recording, and the
/// thumbnail the system shows in the app switcher. Blocking both is what stops
/// an account list full of live codes from leaking to anyone who picks up the
/// phone or scrolls through recent apps.
///
/// This is a capability, not a setting — the caller decides whether to turn it
/// on, based on the user's preference.
abstract interface class ScreenSecurity {
  /// Blocks screen capture for this app.
  Future<void> enable();

  /// Allows screen capture again.
  Future<void> disable();

  /// Whether capture is currently blocked.
  Future<bool> isEnabled();
}

/// A [ScreenSecurity] backed by a platform channel.
///
/// On Android this sets `FLAG_SECURE` on the window. There is no Flutter API for
/// that flag, so it is set from Kotlin — see `MainActivity.kt`.
///
/// On iOS the equivalent requires a `UITextField`-based trick that this build
/// does not implement; the calls are no-ops there rather than errors, so the
/// rest of the app behaves identically on both platforms.
class PlatformScreenSecurity implements ScreenSecurity {
  /// Creates the platform-backed implementation.
  const new();

  /// Must match the channel name in `MainActivity.kt`.
  static const MethodChannel _channel = MethodChannel(
    'moe.nanakura.utaha/screen_security',
  );

  @override
  Future<void> enable() => _invoke('enable');

  @override
  Future<void> disable() => _invoke('disable');

  @override
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      // No implementation on this platform (iOS, or a unit test).
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<bool>(method);
    } on MissingPluginException {
      // Deliberately ignored: this is a best-effort protection, and failing to
      // apply it must not stop the app from working.
    } on PlatformException {
      // Same reasoning.
    }
  }
}

/// A [ScreenSecurity] that only records what was asked of it, for tests.
class FakeScreenSecurity implements ScreenSecurity {
  /// Creates a fake, optionally already enabled.
  new({this.enabled = false});

  /// Whether capture is currently blocked.
  bool enabled;

  /// How many times [enable] was called.
  int enableCount = 0;

  /// How many times [disable] was called.
  int disableCount = 0;

  @override
  Future<void> enable() async {
    enableCount++;
    enabled = true;
  }

  @override
  Future<void> disable() async {
    disableCount++;
    enabled = false;
  }

  @override
  Future<bool> isEnabled() async => enabled;
}
