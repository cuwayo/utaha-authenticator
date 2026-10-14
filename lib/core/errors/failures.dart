/// Domain-level failure types.
///
/// Every failure carries a user-facing `message` written for a person, not a
/// developer: calm, specific and free of jargon. UI code can display it directly,
/// and should never need to pattern-match on the message text — match on the
/// subclass instead.
library;

/// Base class for every recoverable failure the app can present.
sealed class Failure implements Exception {
  const new(this.message, {this.cause});

  /// A short, plain-language explanation safe to show in the UI.
  final String message;

  /// The underlying error, kept for debugging. Never shown to the user and never
  /// logged together with secret material.
  final Object? cause;

  @override
  String toString() => 'Failure: $message';
}

/// A secret key could not be understood.
final class InvalidSecretFailure extends Failure {
  /// Creates a failure for a secret that failed validation.
  const new(super.message, {super.cause});
}

/// An `otpauth://` URI could not be parsed.
final class InvalidOtpAuthUriFailure extends Failure {
  /// Creates a failure for a malformed provisioning URI.
  const new(super.message, {super.cause});
}

/// A Google Authenticator export payload could not be read.
final class MigrationParseFailure extends Failure {
  /// Creates a failure for an unreadable migration payload.
  const new(super.message, {super.cause});
}

/// A backup file could not be read, decrypted or understood.
final class BackupFailure extends Failure {
  /// Creates a failure for a backup problem.
  const new(super.message, {super.cause});
}

/// A backup was written by a newer version of the app than this one understands.
final class UnsupportedBackupVersionFailure extends BackupFailure {
  /// Creates a failure for an unrecognised format version.
  const new(super.message, {super.cause});
}

/// The passphrase supplied for a backup was wrong, or the file was tampered with.
///
/// These two cases are intentionally indistinguishable: AES-GCM cannot tell them
/// apart, and reporting "wrong password" for a tampered file would leak that the
/// ciphertext itself authenticated.
final class BackupAuthenticationFailure extends BackupFailure {
  /// Creates a failure for a failed authentication check.
  const new([
    super.message =
        'That password did not work, or the file has been changed since it was '
        'created.',
  ]);
}

/// A secret could not be stored in or read from the platform keystore.
final class SecureStorageFailure extends Failure {
  /// Creates a failure for a keystore problem.
  const new(super.message, {super.cause});
}

/// The user cancelled a biometric or device-credential prompt.
final class AuthenticationCancelledFailure extends Failure {
  /// Creates a failure for a cancelled prompt.
  const new([super.message = 'Authentication was cancelled.']);
}
