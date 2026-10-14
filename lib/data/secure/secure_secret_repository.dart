import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';

/// Stores OTP secrets in the platform keystore via `flutter_secure_storage`.
///
/// On Android this is AES-GCM data encryption with the key wrapped by an RSA
/// OAEP keypair held in the hardware-backed Keystore; on iOS it is the Keychain
/// with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so secrets are not
/// migrated to a new device by an iCloud backup.
///
/// Values are stored Base64-encoded because the plugin's API is string-based.
/// That is an encoding, not a protection: confidentiality comes from the
/// keystore, not from the encoding.
class SecureSecretRepository implements SecretRepository {
  /// Creates a repository over [storage].
  ///
  /// A single instance should be shared app-wide; it is cheap to hold but the
  /// underlying platform channel is not free to call.
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  final FlutterSecureStorage _storage;

  /// Prefix that namespaces our keys inside the shared keystore.
  static const String _keyPrefix = 'utaha.secret.';

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        // Readable only while the device is unlocked, and never restored onto
        // a different device from a backup.
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    );
  }

  String _key(String accountId) => '$_keyPrefix$accountId';

  @override
  Future<void> write(String accountId, Uint8List secret) async {
    if (secret.isEmpty) {
      throw const SecureStorageFailure(
        'That secret is empty, so there was nothing to save.',
      );
    }
    try {
      await _storage.write(key: _key(accountId), value: base64Encode(secret));
    } on Object catch (error) {
      throw SecureStorageFailure(
        'The secret could not be saved securely on this device.',
        cause: error,
      );
    }
  }

  @override
  Future<Uint8List?> read(String accountId) async {
    final String? encoded;
    try {
      encoded = await _storage.read(key: _key(accountId));
    } on Object catch (error) {
      throw SecureStorageFailure(
        'The secret could not be read from this device.',
        cause: error,
      );
    }
    if (encoded == null) return null;

    try {
      return Uint8List.fromList(base64Decode(encoded));
    } on FormatException catch (error) {
      // The stored value is not something we wrote. Treat it as missing rather
      // than crashing the account list, and let the UI flag the account.
      throw SecureStorageFailure(
        'A stored secret could not be understood and may be damaged.',
        cause: error,
      );
    }
  }

  @override
  Future<void> delete(String accountId) async {
    try {
      await _storage.delete(key: _key(accountId));
    } on Object catch (error) {
      throw SecureStorageFailure(
        'The secret could not be removed from this device.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_keyPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } on Object catch (error) {
      throw SecureStorageFailure(
        'The stored secrets could not be removed from this device.',
        cause: error,
      );
    }
  }

  @override
  Future<Set<String>> accountIds() async {
    try {
      final all = await _storage.readAll();
      return all.keys
          .where((key) => key.startsWith(_keyPrefix))
          .map((key) => key.substring(_keyPrefix.length))
          .toSet();
    } on Object catch (error) {
      throw SecureStorageFailure(
        'The list of stored secrets could not be read from this device.',
        cause: error,
      );
    }
  }
}

/// Convenience for wiping a secret buffer returned by [SecretRepository.read].
///
/// Kept here so call sites do not each need to import the zeroing helpers.
void wipeSecret(Uint8List? secret) => zero(secret);
