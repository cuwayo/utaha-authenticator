import 'dart:typed_data';

/// Stores OTP secret keys.
///
/// Implementations must keep secrets in platform-protected storage (Android
/// Keystore / iOS Keychain) and must never write them to plain files, logs,
/// preferences or crash reports.
///
/// Secrets cross this boundary as raw bytes rather than strings so callers can
/// wipe them with `zero()` when finished. See `core/utils/zeroing.dart` for why
/// strings cannot be reliably zeroed.
abstract interface class SecretRepository {
  /// Stores [secret] under [accountId], replacing any existing value.
  Future<void> write(String accountId, Uint8List secret);

  /// Returns the secret for [accountId], or null when there is none.
  ///
  /// The caller owns the returned buffer and should zero it after use.
  Future<Uint8List?> read(String accountId);

  /// Removes the secret for [accountId]. Succeeds if it was already absent.
  Future<void> delete(String accountId);

  /// Removes every stored secret. Used by "delete all accounts".
  Future<void> deleteAll();

  /// Returns the account ids that currently have a stored secret.
  ///
  /// Used to detect metadata rows whose secret has gone missing, which can
  /// happen if the platform keystore is reset.
  Future<Set<String>> accountIds();
}
