import 'package:utaha_authenticator/domain/models/app_settings.dart';

/// Reads and writes user preferences.
///
/// Settings are not secret, so they live in the local database rather than the
/// keystore. [watch] exists so the UI reacts to changes made elsewhere — for
/// example the theme updating the instant the user toggles dark mode.
abstract interface class SettingsRepository {
  /// Loads the current settings, falling back to [AppSettings.defaults] on a
  /// fresh install.
  Future<AppSettings> load();

  /// Persists [settings].
  Future<void> save(AppSettings settings);

  /// Emits the current settings immediately, then again after every change.
  Stream<AppSettings> watch();
}
