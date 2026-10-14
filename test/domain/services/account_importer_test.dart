import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/services/account_importer.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';

const String _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  late InMemoryAccountRepository accounts;
  late InMemorySecretRepository secrets;
  late AccountService service;
  late AccountImporter importer;

  setUp(() {
    accounts = InMemoryAccountRepository();
    secrets = InMemorySecretRepository();
    service = AccountService(accounts: accounts, secrets: secrets);
    importer = AccountImporter(service);
  });

  group('importUri', () {
    test('adds the account described by the URI', () async {
      final outcome = await importer.importUri(
        'otpauth://totp/GitHub:ada@example.com?secret=$_secret&issuer=GitHub',
      );

      expect(outcome, isA<ImportSucceeded>());
      final account = (outcome as ImportSucceeded).account;
      expect(account.issuer, 'GitHub');
      expect(account.accountName, 'ada@example.com');
      expect(secrets.peek(account.id), Base32.decode(_secret));
    });

    test('carries every parameter through', () async {
      final outcome = await importer.importUri(
        'otpauth://totp/Acme:ada?secret=$_secret&issuer=Acme'
        '&algorithm=SHA512&digits=8&period=60',
      );

      final account = (outcome as ImportSucceeded).account;
      expect(account.algorithm, OtpAlgorithm.sha512);
      expect(account.digits, 8);
      expect(account.period, 60);
    });

    test('adds a counter-based account with its counter', () async {
      final outcome = await importer.importUri(
        'otpauth://hotp/Bank:ada?secret=$_secret&counter=9',
      );

      final account = (outcome as ImportSucceeded).account;
      expect(account.type, OtpType.hotp);
      expect(account.counter, 9);
    });

    test('returns a failure for a malformed URI instead of throwing', () async {
      final outcome = await importer.importUri('not-a-uri');
      expect(outcome, isA<ImportFailed>());
      expect(
        (outcome as ImportFailed).failure,
        isA<InvalidOtpAuthUriFailure>(),
      );
    });

    test('returns a failure for an unsupported digit count', () async {
      final outcome = await importer.importUri(
        'otpauth://totp/ada?secret=$_secret&digits=5',
      );
      expect(outcome, isA<ImportFailed>());
    });

    test('writes nothing when the URI is rejected', () async {
      await importer.importUri('otpauth://totp/ada?secret=$_secret&digits=5');
      expect(await accounts.readAll(), isEmpty);
      expect(await secrets.accountIds(), isEmpty);
    });

    test('a rejected URI does not leak its secret in the message', () async {
      final outcome = await importer.importUri(
        'otpauth://totp/ada?secret=$_secret&digits=5',
      );
      final message = (outcome as ImportFailed).failure.message;
      expect(message, isNot(contains(_secret)));
    });
  });

  group('duplicate detection', () {
    test('reports a duplicate rather than adding it', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada@example.com?secret=$_secret&issuer=GitHub',
      );

      final second = await importer.importUri(
        'otpauth://totp/GitHub:ada@example.com?secret=$_secret&issuer=GitHub',
      );

      expect(second, isA<ImportDuplicate>());
      expect(await accounts.readAll(), hasLength(1));
    });

    test('matching ignores case and surrounding whitespace', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada@example.com?secret=$_secret&issuer=GitHub',
      );

      final second = await importer.importUri(
        'otpauth://totp/%20github%20:ADA%40EXAMPLE.COM?secret=$_secret&issuer=github',
      );

      expect(second, isA<ImportDuplicate>());
    });

    test('a different account name is not a duplicate', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada@example.com?secret=$_secret&issuer=GitHub',
      );
      final second = await importer.importUri(
        'otpauth://totp/GitHub:grace@example.com?secret=$_secret&issuer=GitHub',
      );
      expect(second, isA<ImportSucceeded>());
      expect(await accounts.readAll(), hasLength(2));
    });

    test('a different issuer is not a duplicate', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
      );
      final second = await importer.importUri(
        'otpauth://totp/GitLab:ada?secret=$_secret&issuer=GitLab',
      );
      expect(second, isA<ImportSucceeded>());
    });

    test('force adds the duplicate anyway', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
      );

      final forced = await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
        force: true,
      );

      expect(forced, isA<ImportSucceeded>());
      expect(await accounts.readAll(), hasLength(2));
    });

    test('editing an account is not a duplicate of itself', () async {
      // Re-importing the same details with replaceExistingId must not report the
      // account as colliding with itself.
      final first = await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
      );
      final id = (first as ImportSucceeded).account.id;

      final second = await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
        replaceExistingId: id,
      );

      expect(second, isA<ImportSucceeded>());
      expect(await accounts.readAll(), hasLength(1));
    });
  });

  group('findDuplicates', () {
    test('finds a match by issuer and name', () async {
      await importer.importUri(
        'otpauth://totp/GitHub:ada?secret=$_secret&issuer=GitHub',
      );
      final found = await importer.findDuplicates(
        issuer: 'github',
        accountName: 'ADA',
      );
      expect(found, hasLength(1));
    });

    test('returns nothing when the list is empty', () async {
      expect(
        await importer.findDuplicates(issuer: 'x', accountName: 'y'),
        isEmpty,
      );
    });

    test('treats a missing issuer as an empty issuer', () async {
      await importer.importUri('otpauth://totp/ada?secret=$_secret');
      expect(await importer.findDuplicates(accountName: 'ada'), hasLength(1));
    });
  });

  group('importManual', () {
    test('adds an account from typed values', () async {
      final secret = Base32.decode(_secret);
      final outcome = await importer.importManual(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: secret,
      );

      expect(outcome, isA<ImportSucceeded>());
      expect(await accounts.readAll(), hasLength(1));
    });

    test("does NOT zero the caller's buffer, so a retry still works", () async {
      // The duplicate-retry flow reuses the buffer; wiping it inside the
      // importer would make the second attempt store an empty key.
      final secret = Base32.decode(_secret);
      await importer.importManual(accountName: 'ada', secret: secret);

      expect(
        secret.any((byte) => byte != 0),
        isTrue,
        reason: "importer must leave the caller's buffer intact",
      );
    });

    test('a retry after a duplicate uses the same usable key', () async {
      final secret = Base32.decode(_secret);
      await importer.importManual(accountName: 'ada', secret: secret);
      final retry = await importer.importManual(
        accountName: 'ada',
        secret: secret,
        force: true,
      );

      expect(retry, isA<ImportSucceeded>());
      final account = (retry as ImportSucceeded).account;
      // The stored key must be the real one, not a zeroed buffer.
      expect(secrets.peek(account.id), Base32.decode(_secret));
    });

    test('reports an empty secret as a failure', () async {
      final outcome = await importer.importManual(
        accountName: 'ada',
        secret: Uint8List(0),
      );
      expect(outcome, isA<ImportFailed>());
    });
  });

  group('updateMetadata', () {
    test('renames an account without touching its secret', () async {
      final added = await importer.importManual(
        accountName: 'ada',
        secret: Base32.decode(_secret),
      );
      final account = (added as ImportSucceeded).account;
      final before = secrets.peek(account.id);

      final result = await importer.updateMetadata(
        account.copyWith(accountName: 'grace'),
      );

      expect(result, isA<ImportSucceeded>());
      expect((await accounts.findById(account.id))!.accountName, 'grace');
      expect(secrets.peek(account.id), before);
    });
  });
}
