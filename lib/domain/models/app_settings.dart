import 'package:utaha_authenticator/domain/models/display_preferences.dart';

/// Which theme the user has chosen.
enum AppThemeMode {
  /// Follow the device setting.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark;

  /// Stable identifier used for persistence.
  String get id => name;

  /// Parses [id], falling back to [AppThemeMode.system].
  static AppThemeMode fromId(String? id) => AppThemeMode.values.firstWhere(
    (value) => value.name == id,
    orElse: () => AppThemeMode.system,
  );
}

/// Immutable snapshot of every user-facing preference.
///
/// Values are stored as strings in the local database; `fromMap` and `toMap`
/// are the only places that know about that encoding, so adding a setting means
/// touching one class rather than every call site.
class AppSettings {
  /// Creates a settings snapshot. Prefer `AppSettings.defaults` or `copyWith`.
  const new({
    this.themeMode = AppThemeMode.system,
    this.useDynamicColor = true,
    this.useAmoled = false,
    this.seedColorValue = 0xFF5B3FA6,
    this.tapToReveal = false,
    this.codeGrouping = CodeGrouping.triples,
    this.clipboardClearSeconds = 30,
    this.lockTimeoutSeconds = 30,
    this.listDensity = ListDensity.comfortable,
    this.appLockEnabled = false,
    this.blockScreenshots = true,
    this.onboardingCompleted = false,
  });

  /// Decodes settings from their stored string representation.
  ///
  /// Unknown keys are ignored and malformed values fall back to the default for
  /// that field, so a settings row written by a newer build can never crash an
  /// older one.
  factory fromMap(Map<String, String> map) {
    const fallback = AppSettings.defaults;
    return AppSettings(
      themeMode: AppThemeMode.fromId(map[_kThemeMode]),
      useDynamicColor: _bool(map[_kUseDynamicColor], fallback.useDynamicColor),
      useAmoled: _bool(map[_kUseAmoled], fallback.useAmoled),
      seedColorValue: _int(map[_kSeedColor], fallback.seedColorValue),
      tapToReveal: _bool(map[_kTapToReveal], fallback.tapToReveal),
      codeGrouping: CodeGrouping.fromId(map[_kCodeGrouping]),
      clipboardClearSeconds: _int(
        map[_kClipboardClear],
        fallback.clipboardClearSeconds,
      ),
      lockTimeoutSeconds: _int(map[_kLockTimeout], fallback.lockTimeoutSeconds),
      listDensity: ListDensity.fromId(map[_kListDensity]),
      appLockEnabled: _bool(map[_kAppLock], fallback.appLockEnabled),
      blockScreenshots: _bool(
        map[_kBlockScreenshots],
        fallback.blockScreenshots,
      ),
      onboardingCompleted: _bool(
        map[_kOnboarding],
        fallback.onboardingCompleted,
      ),
    );
  }

  /// The settings a fresh install starts with.
  static const AppSettings defaults = AppSettings();

  /// Whether the app follows the system, or forces light or dark.
  final AppThemeMode themeMode;

  /// Whether to use wallpaper-derived colours when the platform supports it.
  final bool useDynamicColor;

  /// Whether dark mode should use true black for OLED panels.
  final bool useAmoled;

  /// ARGB value of the fallback seed colour.
  final int seedColorValue;

  /// Whether codes start hidden and must be tapped to reveal.
  final bool tapToReveal;

  /// How codes are split for display.
  final CodeGrouping codeGrouping;

  /// How long a copied code stays on the clipboard, in seconds.
  final int clipboardClearSeconds;

  /// How long the app may stay backgrounded before it locks, in seconds.
  ///
  /// Zero means lock as soon as the app is not in front.
  final int lockTimeoutSeconds;

  /// Row density in the account list.
  final ListDensity listDensity;

  /// Whether the app requires biometrics or a device credential to open.
  final bool appLockEnabled;

  /// Whether to block screenshots and hide content in the task switcher.
  final bool blockScreenshots;

  /// Whether the first-run introduction has been dismissed.
  final bool onboardingCompleted;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? useDynamicColor,
    bool? useAmoled,
    int? seedColorValue,
    bool? tapToReveal,
    CodeGrouping? codeGrouping,
    int? clipboardClearSeconds,
    int? lockTimeoutSeconds,
    ListDensity? listDensity,
    bool? appLockEnabled,
    bool? blockScreenshots,
    bool? onboardingCompleted,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      useAmoled: useAmoled ?? this.useAmoled,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      tapToReveal: tapToReveal ?? this.tapToReveal,
      codeGrouping: codeGrouping ?? this.codeGrouping,
      clipboardClearSeconds:
          clipboardClearSeconds ?? this.clipboardClearSeconds,
      lockTimeoutSeconds: lockTimeoutSeconds ?? this.lockTimeoutSeconds,
      listDensity: listDensity ?? this.listDensity,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  /// Encodes these settings for storage.
  Map<String, String> toMap() => <String, String>{
    _kThemeMode: themeMode.id,
    _kUseDynamicColor: useDynamicColor.toString(),
    _kUseAmoled: useAmoled.toString(),
    _kSeedColor: seedColorValue.toString(),
    _kTapToReveal: tapToReveal.toString(),
    _kCodeGrouping: codeGrouping.id,
    _kClipboardClear: clipboardClearSeconds.toString(),
    _kLockTimeout: lockTimeoutSeconds.toString(),
    _kListDensity: listDensity.id,
    _kAppLock: appLockEnabled.toString(),
    _kBlockScreenshots: blockScreenshots.toString(),
    _kOnboarding: onboardingCompleted.toString(),
  };

  /// Decodes a stored boolean, falling back when the value is absent *or*
  /// unrecognised.
  ///
  /// Treating garbage as `false` would silently turn a setting off; falling back
  /// to the default keeps a corrupted row from changing behaviour.
  static bool _bool(String? raw, bool fallback) => switch (raw) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };

  static int _int(String? raw, int fallback) =>
      raw == null ? fallback : (int.tryParse(raw) ?? fallback);

  static const String _kThemeMode = 'theme_mode';
  static const String _kUseDynamicColor = 'use_dynamic_color';
  static const String _kUseAmoled = 'use_amoled';
  static const String _kSeedColor = 'seed_color';
  static const String _kTapToReveal = 'tap_to_reveal';
  static const String _kCodeGrouping = 'code_grouping';
  static const String _kClipboardClear = 'clipboard_clear_seconds';
  static const String _kLockTimeout = 'lock_timeout_seconds';
  static const String _kListDensity = 'list_density';
  static const String _kAppLock = 'app_lock_enabled';
  static const String _kBlockScreenshots = 'block_screenshots';
  static const String _kOnboarding = 'onboarding_completed';
}
