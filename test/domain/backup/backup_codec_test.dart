import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/domain/backup/backup_codec.dart';
import 'package:utaha_authenticator/domain/backup/backup_format.dart';

/// Argon2id parameters that are cheap enough to run in a unit test.
///
/// The production defaults take seconds per call, which would make this suite
/// unusable. The parameter block is written into each file, so a file made with
/// these still decodes — which is exactly the property that makes raising the
/// defaults later safe.
const Argon2idParameters _fast = Argon2idParameters(
  iterations: 1,
  memory: 64,
  parallelism: 1,
  hashLength: 32,
);

Uint8List _plaintext([String text = 'hello, utaha']) =>
    Uint8List.fromList(utf8.encode(text));

void main() {
  group('round trip', () {
    test('decrypts what it encrypted', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'correct horse battery staple',
        parameters: _fast,
      );

      final clear = await BackupCodec.decode(
        file: file,
        password: 'correct horse battery staple',
      );

      expect(utf8.decode(clear), 'hello, utaha');
    });

    test('round-trips an empty-looking but non-empty payload', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext('{}'),
        password: 'pw',
        parameters: _fast,
      );
      final clear = await BackupCodec.decode(file: file, password: 'pw');
      expect(utf8.decode(clear), '{}');
    });

    test('round-trips binary data, including NUL bytes', () async {
      // A JSON payload never contains NUL, but the codec must not care.
      final binary = Uint8List.fromList(List<int>.generate(256, (i) => i));
      final file = await BackupCodec.encode(
        plaintext: binary,
        password: 'pw',
        parameters: _fast,
      );
      final clear = await BackupCodec.decode(file: file, password: 'pw');
      expect(clear, binary);
    });

    test('round-trips a large payload', () async {
      final large = Uint8List.fromList(
        List<int>.generate(200000, (i) => (i * 31) % 256),
      );
      final file = await BackupCodec.encode(
        plaintext: large,
        password: 'pw',
        parameters: _fast,
      );
      expect(await BackupCodec.decode(file: file, password: 'pw'), large);
    });
  });

  group('file structure', () {
    test('starts with the magic bytes', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(file.sublist(0, 5), utf8.encode('UTAHA'));
    });

    test('records the current format version', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(file[5], BackupFormat.currentVersion);
    });

    test('records the KDF identifier', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(file[6], BackupFormat.kdfArgon2id);
    });

    test('writes the KDF parameters it was given', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      final length = file[7];
      final decoded = Argon2idParameters.decode(
        Uint8List.sublistView(file, 8, 8 + length),
      );
      expect(decoded, isNotNull);
      expect(decoded!.iterations, _fast.iterations);
      expect(decoded.memory, _fast.memory);
      expect(decoded.hashLength, _fast.hashLength);
    });

    test('a file is at least the minimum length', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(file.length, greaterThanOrEqualTo(BackupFormat.minimumLength));
    });
  });

  group('password actually affects the key', () {
    // Regression tests for a race that made every password derive the same key.
    //
    // The KDF helper returned its future from inside a `try`/`finally`, so the
    // `finally` zeroed the password buffer *before* Argon2id read it. The KDF
    // then hashed zeros, producing an identical key for every password — and
    // because the failure depended on scheduling, it only showed up sometimes.
    // These tests use a fixed salt and nonce so the comparison is deterministic.

    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 200 + i));

    test('different passwords produce different ciphertext', () async {
      final a = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'password-a',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      final b = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'password-b',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      // Same salt, same nonce, same plaintext: only the password differs, so
      // identical output would mean the password is being ignored.
      expect(a, isNot(b));
    });

    test('a one-character difference in the password is enough', () async {
      final a = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'abcdefgh',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      final b = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'abcdefgi',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      expect(a, isNot(b));
    });

    test(
      'a file cannot be opened with a different password, repeatedly',
      () async {
        // Run several times: the original bug was scheduling-dependent, so a
        // single iteration could pass by luck.
        for (var i = 0; i < 8; i++) {
          final file = await BackupCodec.encode(
            plaintext: _plaintext(),
            password: 'correct-password',
            parameters: _fast,
            salt: salt,
            nonce: nonce,
          );
          await expectLater(
            BackupCodec.decode(file: file, password: 'wrong-password'),
            throwsA(isA<BackupAuthenticationFailure>()),
            reason: 'iteration $i',
          );
        }
      },
    );
  });

  group('randomness', () {
    test('the same plaintext and password give different files', () async {
      // A fresh salt and nonce per file. If these repeated, GCM would lose its
      // confidentiality and authenticity guarantees.
      final a = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      final b = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(a, isNot(b));
    });

    test('the salt and nonce differ between files', () async {
      final a = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      final b = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      final length = a[7];
      final saltStart = 8 + length;
      expect(
        a.sublist(saltStart, saltStart + 16),
        isNot(b.sublist(saltStart, saltStart + 16)),
      );
      final nonceStart = saltStart + 16;
      expect(
        a.sublist(nonceStart, nonceStart + 12),
        isNot(b.sublist(nonceStart, nonceStart + 12)),
      );
    });

    test('an explicit salt and nonce are honoured', () async {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 100 + i));

      final a = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      final b = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
        salt: salt,
        nonce: nonce,
      );
      // Same salt and nonce means deterministic output, which is only safe
      // because both are supplied deliberately.
      expect(a, b);
    });
  });

  group('wrong password', () {
    test('is rejected', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'right',
        parameters: _fast,
      );

      await expectLater(
        BackupCodec.decode(file: file, password: 'wrong'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('is rejected for a password differing only in case', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'Password',
        parameters: _fast,
      );
      await expectLater(
        BackupCodec.decode(file: file, password: 'password'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('is rejected for a password differing only in whitespace', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'password',
        parameters: _fast,
      );
      await expectLater(
        BackupCodec.decode(file: file, password: 'password '),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('never reveals whether the file or the password was wrong', () async {
      // The message must not distinguish "wrong password" from "tampered file",
      // because that distinction is itself information.
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'right',
        parameters: _fast,
      );
      try {
        await BackupCodec.decode(file: file, password: 'wrong');
        fail('expected failure');
      } on BackupAuthenticationFailure catch (error) {
        expect(error.message.toLowerCase(), contains('password'));
        expect(error.message.toLowerCase(), contains('changed'));
      }
    });
  });

  group('corrupted file', () {
    Future<Uint8List> makeFile() => BackupCodec.encode(
      plaintext: _plaintext(),
      password: 'pw',
      parameters: _fast,
    );

    test('a flipped ciphertext byte is detected', () async {
      final file = await makeFile();
      // Flip a byte in the middle of the ciphertext.
      file[file.length - 20] ^= 0xFF;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('a flipped tag byte is detected', () async {
      final file = await makeFile();
      file[file.length - 1] ^= 0xFF;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('a flipped salt byte is detected', () async {
      // The salt is authenticated as part of the header, so changing it fails
      // the tag check rather than silently deriving a different key.
      final file = await makeFile();
      final saltStart = 8 + file[7];
      file[saltStart] ^= 0xFF;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('a flipped nonce byte is detected', () async {
      final file = await makeFile();
      final nonceStart = 8 + file[7] + 16;
      file[nonceStart] ^= 0xFF;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });

    test('a flipped version byte is detected', () async {
      // Version is in the authenticated header, so tampering with it cannot
      // change how the file is interpreted.
      final file = await makeFile();
      file[5] = 1;
      file[5] ^= 0xFF;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<Failure>()),
      );
    });

    test('a truncated file is rejected', () async {
      final file = await makeFile();
      final truncated = Uint8List.sublistView(file, 0, file.length - 8);
      await expectLater(
        BackupCodec.decode(file: truncated, password: 'pw'),
        throwsA(isA<Failure>()),
      );
    });

    test('an empty file is rejected', () async {
      await expectLater(
        BackupCodec.decode(file: Uint8List(0), password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('a file that is only the magic is rejected', () async {
      await expectLater(
        BackupCodec.decode(
          file: Uint8List.fromList(utf8.encode('UTAHA')),
          password: 'pw',
        ),
        throwsA(isA<BackupFailure>()),
      );
    });
  });

  group('wrong file type', () {
    test('a non-backup file is rejected by its magic bytes', () async {
      final notABackup = Uint8List.fromList(
        List<int>.generate(200, (i) => i % 256),
      );
      await expectLater(
        BackupCodec.decode(file: notABackup, password: 'pw'),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.message,
            'message',
            contains('.utaha'),
          ),
        ),
      );
    });

    test('a JSON file is rejected', () async {
      final json = Uint8List.fromList(utf8.encode('{"hello":"world"}' * 20));
      await expectLater(
        BackupCodec.decode(file: json, password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('a truncated PNG is rejected', () async {
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        ...List<int>.filled(120, 0),
      ]);
      await expectLater(
        BackupCodec.decode(file: png, password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });
  });

  group('unsupported version', () {
    test('a file from a newer format is reported clearly', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      // Pretend a future build wrote it.
      file[5] = BackupFormat.currentVersion + 1;

      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(
          isA<UnsupportedBackupVersionFailure>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a version-zero file is rejected as invalid', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      file[5] = 0;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('the current version is accepted', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      expect(file[5], BackupFormat.currentVersion);
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        completes,
      );
    });
  });

  group('unknown KDF', () {
    test('an unrecognised KDF identifier is rejected', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      file[6] = 99;
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.message,
            'message',
            contains('does not understand'),
          ),
        ),
      );
    });
  });

  group('hostile parameters', () {
    test('absurd memory is rejected before any work is done', () async {
      // Without a bound, a file could make decryption allocate gigabytes.
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      // Rewrite the memory cost to 4 GiB.
      const parameterStart = 8;
      ByteData.sublistView(file).setUint32(parameterStart + 4, 4 * 1024 * 1024);

      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.message,
            'message',
            contains('cannot handle safely'),
          ),
        ),
      );
    });

    test('absurd iterations are rejected', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      ByteData.sublistView(file).setUint32(8, 100000);
      await expectLater(
        BackupCodec.decode(file: file, password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });
  });

  group('input validation', () {
    test('an empty password is rejected on encode', () async {
      await expectLater(
        BackupCodec.encode(plaintext: _plaintext(), password: ''),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('an empty password is rejected on decode', () async {
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: 'pw',
        parameters: _fast,
      );
      await expectLater(
        BackupCodec.decode(file: file, password: ''),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('empty plaintext is rejected', () async {
      await expectLater(
        BackupCodec.encode(
          plaintext: Uint8List(0),
          password: 'pw',
          parameters: _fast,
        ),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('a salt of the wrong length is rejected', () async {
      await expectLater(
        BackupCodec.encode(
          plaintext: _plaintext(),
          password: 'pw',
          parameters: _fast,
          salt: Uint8List(8),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a nonce of the wrong length is rejected', () async {
      await expectLater(
        BackupCodec.encode(
          plaintext: _plaintext(),
          password: 'pw',
          parameters: _fast,
          nonce: Uint8List(4),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('unicode passwords', () {
    test('a password with non-ASCII characters works', () async {
      const password = 'パスワード🔐';
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: password,
        parameters: _fast,
      );
      final clear = await BackupCodec.decode(file: file, password: password);
      expect(utf8.decode(clear), 'hello, utaha');
    });

    test('a password with combining characters is byte-exact', () async {
      // 'é' as one code point vs 'e' + combining acute. These must not be
      // treated as equal, or two visually identical passwords would both work.
      const composed = 'café';
      const decomposed = 'café';
      final file = await BackupCodec.encode(
        plaintext: _plaintext(),
        password: composed,
        parameters: _fast,
      );
      await expectLater(
        BackupCodec.decode(file: file, password: decomposed),
        throwsA(isA<BackupAuthenticationFailure>()),
      );
    });
  });

  group('parameter block encoding', () {
    test('round-trips through encode and decode', () {
      const parameters = Argon2idParameters(
        iterations: 7,
        memory: 12345,
        parallelism: 3,
        hashLength: 48,
      );
      final decoded = Argon2idParameters.decode(parameters.encode());
      expect(decoded, isNotNull);
      expect(decoded!.iterations, 7);
      expect(decoded.memory, 12345);
      expect(decoded.parallelism, 3);
      expect(decoded.hashLength, 48);
    });

    test('rejects a block that is too short', () {
      expect(Argon2idParameters.decode(Uint8List(4)), isNull);
    });

    test('rejects a block with zero values', () {
      final zeroed = Uint8List(10);
      expect(Argon2idParameters.decode(zeroed), isNull);
    });
  });
}
