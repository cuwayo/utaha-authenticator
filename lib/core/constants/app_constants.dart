/// Application-wide constants: identity, URLs, MIME types and defaults.
///
/// These are the single source of truth for values that must stay consistent
/// across Dart code, the Android manifest and the iOS bundle configuration.
library;

/// Human-readable application name shown in the UI.
const String kAppDisplayName = 'Utaha Authenticator';

/// Dart package name, as declared in `pubspec.yaml`.
const String kAppPackageName = 'utaha_authenticator';

/// Reverse-DNS identifier used as the Android `applicationId` and iOS bundle ID.
const String kAppApplicationId = 'moe.nanakura.utaha';

/// Project website.
const String kAppWebsite = 'https://nanakura.moe';

/// Source repository.
const String kAppRepositoryUrl =
    'https://github.com/nanakura/utaha-authenticator';

/// Extension for encrypted backup files.
const String kBackupFileExtension = 'utaha';

/// MIME type registered for encrypted backup files.
///
/// Registered in the Android manifest so the app appears in "Open with" for
/// `.utaha` files picked from a file manager.
const String kBackupMimeType = 'application/vnd.nanakura.utaha-backup';

/// URI scheme used by `otpauth://` provisioning URIs (RFC 6238 appendix A).
const String kOtpAuthScheme = 'otpauth';

/// Scheme used by Google Authenticator's bulk-export URIs.
const String kOtpMigrationScheme = 'otpauth-migration';

/// Fallback seed colour used when dynamic (wallpaper) colour is unavailable.
///
/// A deep violet/indigo, chosen to remain legible in both light and dark
/// schemes when the tonal palette is generated from it.
const int kSeedColorValue = 0xFF5B3FA6;
