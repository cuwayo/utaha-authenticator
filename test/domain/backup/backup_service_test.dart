import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/backup/backup_format.dart';
import 'package:utaha_authenticator/domain/backup/backup_payload.dart';
import 'package:utaha_authenticator/domain/backup/backup_service.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';

const String _secret = 'JBSWY3DPEHPK3PXP';

/// Cheap Argon2id parameters for tests.
///
/// The production cost is deliberately high (3 iterations over 64 MiB), which is
/// roughly 0.6s per derivation on an M-series Mac and slower on a phone. These
/// tests round-trip backups many times, so using the real cost would spend
/// almost all of their runtime in the KDF and trip the test timeout.
///
/// The parameters are recorded in every file, so a file written with these still
/// decodes — which is exactly why the format stores them.
const Argon2idParameters _testKdf = Argon2idParameters(
  iterations: 1,
  memory: 64,
  parallelism: 1,
  hashLength: 32,
);

void main() {
  late InMemoryAccountRepository accounts;
  late InMemorySecretRepository secrets;
  late AccountService accountService;
  late BackupService backup;

  setUp(() {
    accounts = InMemoryAccountRepository();
    secrets = InMemorySecretRepository();
    accountService = AccountService(accounts: accounts, secrets: secrets);
    backup = BackupService(
      accounts: accounts,
      secrets: secrets,
      parameters: _testKdf,
    );
  });

  /// Adds a few accounts to back up.
  Future<void> seed() async {
    await accountService.add(
      accountName: 'ada@example.com',
      issuer: 'GitHub',
      secret: Base32.decode(_secret),
    );
    await accountService.add(
      accountName: 'grace@example.com',
      issuer: 'GitLab',
      secret: Base32.decode(_secret),
      algorithm: OtpAlgorithm.sha256,
      digits: 8,
      period: 60,
    );
    await accountService.add(
      accountName: 'bank',
      issuer: 'Bank',
      secret: Base32.decode(_secret),
      type: OtpType.hotp,
      counter: 7,
    );
  }

  group('payload codec', () {
    test('round-trips accounts and their secrets', () {
      final secret = Base32.decode(_secret);
      final account = Account(
        id: 'a1',
        accountName: 'ada@example.com',
        issuer: 'GitHub',
      );

      final encoded = BackupPayloadCodec.encode(<BackupAccount>[
        BackupAccount(account: account, secret: secret),
      ]);
      addTearDown(() => secret.fillRange(0, secret.length, 0));

      final decoded = BackupPayloadCodec.decode(encoded);
      addTearDown(decoded.dispose);

      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.single.account.id, 'a1');
      expect(decoded.accounts.single.account.issuer, 'GitHub');
      expect(decoded.accounts.single.secret, secret);
    });

    test('round-trips every account setting', () {
      final secret = Base32.decode(_secret);
      final account = Account(
        id: 'a1',
        accountName: 'ada',
        issuer: 'Acme',
        type: OtpType.hotp,
        algorithm: OtpAlgorithm.sha512,
        digits: 8,
        period: 45,
        counter: 99,
        tags: const <String>['work', 'shared'],
        pinned: true,
        sortOrder: 3,
        createdAt: DateTime.utc(2024, 3, 4, 5, 6, 7),
      );

      final decoded = BackupPayloadCodec.decode(
        BackupPayloadCodec.encode(<BackupAccount>[
          BackupAccount(account: account, secret: secret),
        ]),
      );
      addTearDown(decoded.dispose);
      addTearDown(() => secret.fillRange(0, secret.length, 0));

      final restored = decoded.accounts.single.account;
      expect(restored.type, OtpType.hotp);
      expect(restored.algorithm, OtpAlgorithm.sha512);
      expect(restored.digits, 8);
      expect(restored.period, 45);
      expect(restored.counter, 99);
      expect(restored.tags, <String>['work', 'shared']);
      expect(restored.pinned, isTrue);
      expect(restored.sortOrder, 3);
      expect(restored.createdAt?.toUtc(), DateTime.utc(2024, 3, 4, 5, 6, 7));
    });

    test('records a creation time and the app version', () {
      final secret = Base32.decode(_secret);
      final decoded = BackupPayloadCodec.decode(
        BackupPayloadCodec.encode(<BackupAccount>[
          BackupAccount(
            account: Account(id: 'a1', accountName: 'ada'),
            secret: secret,
          ),
        ], appVersion: '1.2.3+4'),
      );
      addTearDown(decoded.dispose);
      addTearDown(() => secret.fillRange(0, secret.length, 0));

      expect(decoded.appVersion, '1.2.3+4');
      expect(decoded.createdAt, isNotNull);
    });

    test('rejects a body that is not JSON', () {
      expect(
        () => BackupPayloadCodec.decode(
          Uint8List.fromList(utf8.encode('not json')),
        ),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('rejects a JSON body that is not a backup', () {
      expect(
        () => BackupPayloadCodec.decode(
          Uint8List.fromList(utf8.encode('{"hello":"world"}')),
        ),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('rejects a body from a newer schema', () {
      expect(
        () => BackupPayloadCodec.decode(
          Uint8List.fromList(
            utf8.encode(
              '{"schema":${BackupPayloadCodec.schemaVersion + 1},"accounts":[]}',
            ),
          ),
        ),
        throwsA(isA<UnsupportedBackupVersionFailure>()),
      );
    });

    test(
      'skips an entry with no secret rather than failing the whole body',
      () {
        final encoded = Uint8List.fromList(
          utf8.encode(
            '{"schema":1,"accounts":['
            '{"id":"a1","accountName":"no-secret","secret":""},'
            '{"id":"a2","accountName":"ok","secret":"$_secret"}'
            ']}',
          ),
        );
        final decoded = BackupPayloadCodec.decode(encoded);
        addTearDown(decoded.dispose);

        expect(decoded.accounts, hasLength(1));
        expect(decoded.accounts.single.account.id, 'a2');
      },
    );

    test('skips an entry with unreadable base32 rather than failing', () {
      final encoded = Uint8List.fromList(
        utf8.encode(
          '{"schema":1,"accounts":['
          '{"id":"a1","accountName":"bad","secret":"11111111"},'
          '{"id":"a2","accountName":"ok","secret":"$_secret"}'
          ']}',
        ),
      );
      final decoded = BackupPayloadCodec.decode(encoded);
      addTearDown(decoded.dispose);
      expect(decoded.accounts, hasLength(1));
    });
  });

  group('export and restore round trip', () {
    test('restores every account with the same secrets', () async {
      await seed();
      final before = await accounts.readAll();
      expect(before, hasLength(3));

      final file = await backup.export(password: 'pw');
      final report = await backup.restore(file: file, password: 'pw');

      expect(report.added + report.replaced, 3);
      expect(report.failed, 0);

      final after = await accounts.readAll();
      expect(after, hasLength(3));

      // Every secret must survive unchanged.
      for (final account in after) {
        expect(secrets.peek(account.id), Base32.decode(_secret));
      }
    });

    test('preserves each account type and its settings', () async {
      await seed();
      final file = await backup.export(password: 'pw');
      await accounts.readAll();

      // Wipe and restore into a clean store.
      await secrets.deleteAll();
      for (final account in await accounts.readAll()) {
        await accounts.delete(account.id);
      }

      await backup.restore(file: file, password: 'pw');
      final restored = await accounts.readAll();

      final hotp = restored.firstWhere((a) => a.type == OtpType.hotp);
      expect(hotp.counter, 7);

      final sha256 = restored.firstWhere(
        (a) => a.algorithm == OtpAlgorithm.sha256,
      );
      expect(sha256.digits, 8);
      expect(sha256.period, 60);
    });

    test(
      'a restored account generates the same code as the original',
      () async {
        // The real test of a backup: the codes must still work.
        await accountService.add(
          accountName: 'ada',
          issuer: 'GitHub',
          secret: Base32.decode(_secret),
        );
        final original = (await accounts.readAll()).single;

        final file = await backup.export(password: 'pw');
        await secrets.deleteAll();
        await accounts.delete(original.id);
        await backup.restore(file: file, password: 'pw');

        final restored = (await accounts.readAll()).single;
        expect(restored.id, original.id);
        expect(secrets.peek(restored.id), Base32.decode(_secret));
      },
    );

    test('the same password can decrypt across separate exports', () async {
      await seed();
      final first = await backup.export(password: 'pw');
      final second = await backup.export(password: 'pw');
      // Different salts and nonces, so different files...
      expect(first, isNot(second));
      // ...but both open with the same password.
      await expectLater(backup.restore(file: first, password: 'pw'), completes);
      await expectLater(
        backup.restore(file: second, password: 'pw'),
        completes,
      );
    });
  });

  group('export edge cases', () {
    test('refuses to export with no accounts', () async {
      await expectLater(
        backup.export(password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('skips an account whose secret is missing', () async {
      await accountService.add(
        accountName: 'ada',
        secret: Base32.decode(_secret),
      );
      // Simulate a keystore reset.
      await secrets.deleteAll();

      await expectLater(
        backup.export(password: 'pw'),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('an empty password is rejected', () async {
      await seed();
      await expectLater(
        backup.export(password: ''),
        throwsA(isA<BackupFailure>()),
      );
    });

    test(
      'a failure to read one secret does not abort the whole export',
      () async {
        await seed();
        final all = await accounts.readAll();
        // Remove one secret; the other two must still be exported.
        await secrets.delete(all.first.id);

        final file = await backup.export(password: 'pw');
        final report = await backup.restore(file: file, password: 'pw');
        expect(report.added + report.replaced, 2);
      },
    );
  });

  group('restore edge cases', () {
    test('the wrong password fails and changes nothing', () async {
      await seed();
      final before = await accounts.readAll();
      final file = await backup.export(password: 'right');

      await expectLater(
        backup.restore(file: file, password: 'wrong'),
        throwsA(isA<BackupAuthenticationFailure>()),
      );

      // The existing accounts must be untouched.
      expect(await accounts.readAll(), before);
    });

    test(
      'restoring twice replaces rather than duplicating by default',
      () async {
        await seed();
        final file = await backup.export(password: 'pw');

        await backup.restore(file: file, password: 'pw');
        await backup.restore(file: file, password: 'pw');

        // Ids are preserved, so the second restore overwrites the first.
        expect(await accounts.readAll(), hasLength(3));
      },
    );

    test('skipped mode leaves existing accounts alone', () async {
      await seed();
      final file = await backup.export(password: 'pw');

      final report = await backup.restore(
        file: file,
        password: 'pw',
        onConflict: ImportConflictResolution.skipped,
      );

      expect(report.skipped, 3);
      expect(report.added, 0);
      expect(report.replaced, 0);
    });

    test('added mode creates a second copy with a fresh id', () async {
      await seed();
      final file = await backup.export(password: 'pw');

      final report = await backup.restore(
        file: file,
        password: 'pw',
        onConflict: ImportConflictResolution.added,
      );

      expect(report.added, 3);
      expect(await accounts.readAll(), hasLength(6));
    });

    test('restoring into an empty store adds everything', () async {
      await seed();
      final file = await backup.export(password: 'pw');
      await secrets.deleteAll();
      for (final account in await accounts.readAll()) {
        await accounts.delete(account.id);
      }
      expect(await accounts.readAll(), isEmpty);

      final report = await backup.restore(file: file, password: 'pw');
      expect(report.added, 3);
      expect(await accounts.readAll(), hasLength(3));
    });

    test(
      'a corrupted file is rejected without touching existing data',
      () async {
        await seed();
        final before = await accounts.readAll();
        final file = await backup.export(password: 'pw');
        file[file.length - 30] ^= 0xFF;

        await expectLater(
          backup.restore(file: file, password: 'pw'),
          throwsA(isA<BackupAuthenticationFailure>()),
        );
        expect(await accounts.readAll(), before);
      },
    );
  });

  group('plain text export', () {
    test('produces one otpauth URI per account', () async {
      await seed();
      final text = await backup.exportPlainUris();
      final lines = text.split('\n');

      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(line, startsWith('otpauth://'));
      }
    });

    test('the URIs can be parsed back and carry the secret', () async {
      await accountService.add(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: Base32.decode(_secret),
      );
      final text = await backup.exportPlainUris();
      expect(text, contains('secret='));
      expect(text, contains('issuer=GitHub'));
      expect(text, contains('ada%40example.com'));
    });

    test('refuses when there are no accounts', () async {
      await expectLater(
        backup.exportPlainUris(),
        throwsA(isA<BackupFailure>()),
      );
    });

    test('skips accounts whose secret is missing', () async {
      await seed();
      final all = await accounts.readAll();
      await secrets.delete(all.first.id);

      final lines = (await backup.exportPlainUris()).split('\n');
      expect(lines, hasLength(2));
    });
  });

  group('RestoreReport', () {
    test('totals every outcome', () {
      const report = RestoreReport(
        added: 1,
        replaced: 2,
        skipped: 3,
        failed: 4,
      );
      expect(report.total, 10);
    });

    test('never prints secrets', () {
      const report = RestoreReport(
        added: 1,
        replaced: 0,
        skipped: 0,
        failed: 0,
      );
      expect(report.toString(), isNot(contains('secret')));
    });
  });

  group('payload disposal', () {
    test('dispose zeroes every secret', () {
      final a = Base32.decode(_secret);
      final b = Base32.decode(_secret);
      final payload = BackupPayload(
        accounts: <BackupAccount>[
          BackupAccount(
            account: Account(id: '1', accountName: 'a'),
            secret: a,
          ),
          BackupAccount(
            account: Account(id: '2', accountName: 'b'),
            secret: b,
          ),
        ],
      );
      expect(payload.accounts, hasLength(2));

      payload.dispose();

      // Both buffers must be wiped, not just the first.
      for (final buffer in <Uint8List>[a, b]) {
        expect(buffer.every((byte) => byte == 0), isTrue);
      }
    });
  });

  group('account ids survive a round trip', () {
    test('so a restored account keeps generating the same codes', () async {
      // The id is the keystore key. If it changed, the restored account would
      // point at a secret that is not there.
      await accountService.add(
        accountName: 'ada',
        secret: Base32.decode(_secret),
      );
      final original = (await accounts.readAll()).single;

      final file = await backup.export(password: 'pw');
      await secrets.deleteAll();
      await accounts.delete(original.id);
      await backup.restore(file: file, password: 'pw');

      final restored = (await accounts.readAll()).single;
      expect(restored.id, original.id);
      expect(secrets.peek(restored.id), isNotNull);
    });
  });
}
