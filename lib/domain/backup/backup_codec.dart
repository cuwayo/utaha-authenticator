import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/backup/backup_format.dart';

/// Encrypts and decrypts `.utaha` backup files.
///
/// Layout and rationale are documented on [BackupFormat]. The short version:
/// Argon2id derives a 256-bit key from the user's password, AES-256-GCM
/// encrypts the payload, and the header is authenticated as additional data so
/// it cannot be altered without detection.
///
/// **Cost warning:** Argon2id with the default parameters takes a few seconds
/// on a phone in pure Dart. Callers should run [encode] and [decode] off the
/// UI thread (in an isolate) and show progress.
abstract final class BackupCodec {
  /// Encrypts [plaintext] under [password].
  ///
  /// Returns the complete file contents.
  ///
  /// The caller owns [plaintext] and should zero it afterwards; the secrets of
  /// every account are inside it.
  static Future<Uint8List> encode({
    required Uint8List plaintext,
    required String password,
    Argon2idParameters parameters = BackupFormat.argon2id,
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    if (plaintext.isEmpty) {
      throw const BackupFailure('There is nothing to back up yet.');
    }
    _checkPassword(password);

    // A fresh random salt and nonce per file. Reusing either across backups
    // would be a serious flaw: a repeated nonce under the same key breaks
    // GCM's confidentiality and authenticity guarantees outright.
    final resolvedSalt = salt ?? _randomBytes(BackupFormat.saltLength);
    final resolvedNonce = nonce ?? _randomBytes(BackupFormat.nonceLength);
    if (resolvedSalt.length != BackupFormat.saltLength) {
      throw ArgumentError('salt must be ${BackupFormat.saltLength} bytes');
    }
    if (resolvedNonce.length != BackupFormat.nonceLength) {
      throw ArgumentError('nonce must be ${BackupFormat.nonceLength} bytes');
    }

    final header = _buildHeader(
      parameters: parameters,
      salt: resolvedSalt,
      nonce: resolvedNonce,
    );

    final key = await _deriveKey(password, resolvedSalt, parameters);
    try {
      final box = await AesGcm.with256bits().encrypt(
        plaintext,
        secretKey: key,
        nonce: resolvedNonce,
        // Authenticating the header binds the version, KDF parameters and salt
        // to the ciphertext.
        aad: header,
      );

      final out = BytesBuilder(copy: false)
        ..add(header)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      return out.takeBytes();
    } finally {
      // The derived key is as sensitive as the password.
      await _destroyKey(key);
    }
  }

  /// Decrypts a `.utaha` file with [password].
  ///
  /// Throws [UnsupportedBackupVersionFailure] for a file from a newer format,
  /// [BackupAuthenticationFailure] for a wrong password or a tampered file, and
  /// [BackupFailure] for anything structurally wrong.
  static Future<Uint8List> decode({
    required Uint8List file,
    required String password,
  }) async {
    _checkPassword(password);

    if (file.length < BackupFormat.minimumLength) {
      throw const BackupFailure(
        'That file is too small to be a backup. It may be incomplete or '
        'damaged.',
      );
    }

    // 1. Magic.
    for (var i = 0; i < BackupFormat.magic.length; i++) {
      if (file[i] != BackupFormat.magic[i]) {
        throw const BackupFailure(
          'That is not a Utaha backup file. Choose a file that ends in '
          '".utaha".',
        );
      }
    }

    // 2. Format version.
    final version = file[5];
    if (version > BackupFormat.currentVersion) {
      throw const UnsupportedBackupVersionFailure(
        'That backup was made by a newer version of the app. Update the app, '
        'then try again.',
      );
    }
    if (version == 0) {
      throw const BackupFailure(
        'That backup file is not valid. It may be damaged.',
      );
    }

    // 3. KDF.
    final kdfId = file[6];
    if (kdfId != BackupFormat.kdfArgon2id) {
      throw const BackupFailure(
        'That backup uses a kind of protection this version of the app does '
        'not understand.',
      );
    }

    // 4. Parameters, salt and nonce.
    final parameterLength = file[7];
    const parametersStart = 8;
    final saltStart = parametersStart + parameterLength;
    final nonceStart = saltStart + BackupFormat.saltLength;
    final cipherStart = nonceStart + BackupFormat.nonceLength;

    if (cipherStart + BackupFormat.tagLength > file.length) {
      throw const BackupFailure(
        'That backup file is incomplete. It may have been cut short while '
        'being copied.',
      );
    }

    final parameters = Argon2idParameters.decode(
      Uint8List.sublistView(file, parametersStart, saltStart),
    );
    if (parameters == null) {
      throw const BackupFailure(
        'That backup file is not valid. It may be damaged.',
      );
    }

    final salt = Uint8List.fromList(
      Uint8List.sublistView(file, saltStart, nonceStart),
    );
    final nonce = Uint8List.fromList(
      Uint8List.sublistView(file, nonceStart, cipherStart),
    );
    final header = Uint8List.fromList(
      Uint8List.sublistView(file, 0, cipherStart),
    );
    final cipherText = Uint8List.sublistView(
      file,
      cipherStart,
      file.length - BackupFormat.tagLength,
    );
    final macBytes = Uint8List.sublistView(
      file,
      file.length - BackupFormat.tagLength,
    );

    // A hostile file could ask for absurd KDF parameters and use the decryption
    // attempt as a denial-of-service. Bound them before doing any work.
    _checkParametersAreReasonable(parameters);

    final key = await _deriveKey(password, salt, parameters);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
        aad: header,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      // A wrong password and a tampered file are indistinguishable here, and
      // saying which would leak whether the ciphertext authenticated.
      throw const BackupAuthenticationFailure();
    } finally {
      await _destroyKey(key);
      zero(salt);
    }
  }

  /// Rejects parameter blocks that would make decryption pathologically slow.
  ///
  /// Without this, a file declaring a terabyte of memory or a million
  /// iterations would hang or crash the app.
  static void _checkParametersAreReasonable(Argon2idParameters parameters) {
    const maxMemoryKib = 1024 * 1024; // 1 GiB
    const maxIterations = 64;
    const maxParallelism = 64;
    const maxHashLength = 64;

    if (parameters.memory > maxMemoryKib ||
        parameters.iterations > maxIterations ||
        parameters.parallelism > maxParallelism ||
        parameters.hashLength > maxHashLength) {
      throw const BackupFailure(
        'That backup asks for settings this app cannot handle safely. It may '
        'be damaged.',
      );
    }
  }

  /// Builds the authenticated header.
  static Uint8List _buildHeader({
    required Argon2idParameters parameters,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final encodedParameters = parameters.encode();
    final out = BytesBuilder(copy: false)
      ..add(BackupFormat.magic)
      ..addByte(BackupFormat.currentVersion)
      ..addByte(BackupFormat.kdfArgon2id)
      ..addByte(encodedParameters.length)
      ..add(encodedParameters)
      ..add(salt)
      ..add(nonce);
    return out.takeBytes();
  }

  /// Derives the AES key from [password].
  ///
  /// Must be `async` and must `await` the derivation: `SecretKeyData` holds the
  /// password buffer by reference, so zeroing it before Argon2id has finished
  /// reading would feed the KDF zeros instead of the password. Returning the
  /// future from inside `try`/`finally` would run the `finally` immediately and
  /// make derivation read a zeroed buffer — which silently produces the *same*
  /// key for every password, so any password would open the file.
  static Future<SecretKey> _deriveKey(
    String password,
    Uint8List salt,
    Argon2idParameters parameters,
  ) async {
    // The password is encoded to UTF-8 bytes for the KDF. Those bytes cannot be
    // zeroed (Dart strings are immutable), so they are held for as short a time
    // as possible here.
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    try {
      return await parameters.toArgon2id().deriveKey(
        secretKey: SecretKeyData(passwordBytes),
        nonce: salt,
      );
    } finally {
      zero(passwordBytes);
    }
  }

  /// Overwrites a derived key's bytes in place.
  static Future<void> _destroyKey(SecretKey key) async {
    try {
      final bytes = await key.extractBytes();
      zero(Uint8List.fromList(bytes));
    } on Object {
      // Best effort: some key types cannot be extracted. The key is dropped
      // from scope either way.
    }
  }

  static void _checkPassword(String password) {
    if (password.isEmpty) {
      throw const BackupFailure('Please enter a password.');
    }
  }

  /// Cryptographically secure random bytes.
  ///
  /// `Random.secure()` is explicitly the CSPRNG; the ordinary `Random()` would
  /// be predictable and would make both the salt and the nonce guessable.
  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
