import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The encrypted backup file format.
///
/// A `.utaha` file is:
///
/// ```text
/// offset  size  field
/// 0       5     magic, ASCII "UTAHA"
/// 5       1     format version
/// 6       1     kdf id
/// 7       1     kdf parameter block length
/// 8       n     kdf parameters
/// 8+n     16    salt
/// 24+n    12    nonce
/// 36+n    ...   ciphertext followed by the 16-byte GCM tag
/// ```
///
/// The header (magic through nonce) is passed to AES-GCM as additional
/// authenticated data, so tampering with the version, the KDF parameters or the
/// salt causes decryption to fail rather than silently changing how the
/// ciphertext is interpreted.
///
/// The format version is a single byte at a fixed offset and the KDF is
/// identified by id rather than assumed, so a future build can add PBKDF2 or
/// change the KDF parameters without breaking files written today.
abstract final class BackupFormat {
  /// ASCII magic that identifies the file.
  static final Uint8List magic = Uint8List.fromList(utf8.encode('UTAHA'));

  /// The format version this build writes.
  static const int currentVersion = 1;

  /// Key-derivation function identifiers.
  static const int kdfArgon2id = 1;

  /// Length of the salt in bytes.
  static const int saltLength = 16;

  /// Length of the AES-GCM nonce in bytes.
  static const int nonceLength = 12;

  /// Length of the AES-GCM authentication tag in bytes.
  static const int tagLength = 16;

  /// Smallest possible file: header with no KDF parameters, plus tag.
  static int get minimumLength =>
      magic.length + 1 + 1 + 1 + saltLength + nonceLength + tagLength;

  /// Argon2id parameters.
  ///
  /// These are deliberately expensive. A backup file is the one artefact that
  /// can leave the device, so it is the one place where an attacker gets to
  /// attack offline with unlimited attempts — the cost of a few seconds on
  /// export is worth making that attack impractical.
  ///
  /// The parameters are written into every file, so raising them later does not
  /// invalidate backups made now.
  static const Argon2idParameters argon2id = Argon2idParameters(
    // Iterations. Higher is slower for both sides.
    iterations: 3,
    // 64 MiB. This is the parameter that hurts GPU-based cracking most.
    memory: 65536,
    // Threads; the pure-Dart implementation is single-threaded, so this is
    // recorded for compatibility rather than used for parallelism.
    parallelism: 4,
    // 32-byte key for AES-256.
    hashLength: 32,
  );
}

/// Argon2id parameters, as written into a backup file.
class Argon2idParameters {
  /// Creates a parameter set.
  const new({
    required this.iterations,
    required this.memory,
    required this.parallelism,
    required this.hashLength,
  });

  /// Number of passes over memory.
  final int iterations;

  /// Memory cost in kibibytes.
  final int memory;

  /// Degree of parallelism.
  final int parallelism;

  /// Derived key length in bytes.
  final int hashLength;

  /// Encodes the parameters as a compact binary block.
  Uint8List encode() {
    final bytes = Uint8List(4 + 4 + 1 + 1);
    ByteData.sublistView(bytes)
      ..setUint32(0, iterations)
      ..setUint32(4, memory);
    bytes[8] = parallelism;
    bytes[9] = hashLength;
    return bytes;
  }

  /// Decodes a parameter block, or null when it is malformed.
  static Argon2idParameters? decode(Uint8List bytes) {
    if (bytes.length < 10) return null;
    final view = ByteData.sublistView(bytes);
    final iterations = view.getUint32(0);
    final memory = view.getUint32(4);
    final parallelism = bytes[8];
    final hashLength = bytes[9];
    if (iterations == 0 || memory == 0 || hashLength == 0) return null;
    return Argon2idParameters(
      iterations: iterations,
      memory: memory,
      parallelism: parallelism,
      hashLength: hashLength,
    );
  }

  /// The equivalent `cryptography` parameter set.
  Argon2id toArgon2id() => Argon2id(
    parallelism: parallelism,
    memory: memory,
    iterations: iterations,
    hashLength: hashLength,
  );

  @override
  String toString() =>
      'Argon2idParameters(iterations: $iterations, memory: ${memory}KiB, '
      'parallelism: $parallelism, hashLength: $hashLength)';
}

/// The bytes of an encoded backup, kept separate from the file so the caller
/// decides how it is written.
class EncodedBackup {
  /// Creates an encoded backup.
  const new(this.bytes);

  /// The complete file contents.
  final Uint8List bytes;
}
