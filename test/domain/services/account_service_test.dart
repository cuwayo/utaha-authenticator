import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';

/// A valid 10-byte secret.
Uint8List _secret() => Base32.decode('JBSWY3DPEHPK3PXP');

void main() {
  late InMemoryAccountRepository accounts;
  late InMemorySecretRepository secrets;
  late AccountService service;

  setUp(() {
    accounts = InMemoryAccountRepository();
    secrets = InMemorySecretRepository();
    service = AccountService(accounts: accounts, secrets: secrets);
  });

  group('AccountService.add', () {
    test('stores the secret and the metadata', () async {
      final secret = _secret();
      final account = await service.add(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: secret,
      );

      expect(await accounts.findById(account.id), isNotNull);
      expect(secrets.peek(account.id), secret);
    });

    test('writes the secret BEFORE the metadata', () async {
      // The account list is driven by metadata, so writing the secret first
      // means no row can ever be shown that has no key behind it.
      await service.add(accountName: 'ada', secret: _secret());

      final id = secrets.writeLog.single;
      expect(
        await accounts.findById(id),
        isNotNull,
        reason: 'metadata must exist once the secret write is recorded',
      );
    });

    test("does not retain or mutate the caller's secret buffer", () async {
      final secret = _secret();
      final original = Uint8List.fromList(secret);

      final account = await service.add(accountName: 'ada', secret: secret);
      // The caller still owns the buffer; zeroing it must not affect storage.
      zero(secret);

      expect(secrets.peek(account.id), original);
    });

    test('rolls the secret back when the metadata write fails', () async {
      // A failed add must not leave a secret with no account pointing at it.
      final failing = _FailingAccountRepository();
      final failingService = AccountService(
        accounts: failing,
        secrets: secrets,
      );

      await expectLater(
        failingService.add(accountName: 'ada', secret: _secret()),
        throwsA(isA<Exception>()),
      );
      expect(await secrets.accountIds(), isEmpty);
    });

    test('appends new accounts to the end of the ordering', () async {
      final first = await service.add(accountName: 'one', secret: _secret());
      final second = await service.add(accountName: 'two', secret: _secret());
      final third = await service.add(accountName: 'three', secret: _secret());

      expect(first.sortOrder, 0);
      expect(second.sortOrder, 1);
      expect(third.sortOrder, 2);
    });

    test('trims whitespace and blanks an empty issuer', () async {
      final account = await service.add(
        accountName: '  ada@example.com  ',
        issuer: '   ',
        secret: _secret(),
      );
      expect(account.accountName, 'ada@example.com');
      expect(account.issuer, isNull);
    });

    test('rejects an empty account name', () async {
      await expectLater(
        service.add(accountName: '   ', secret: _secret()),
        throwsA(
          isA<InvalidSecretFailure>().having(
            (e) => e.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('rejects an empty secret', () async {
      await expectLater(
        service.add(accountName: 'ada', secret: Uint8List(0)),
        throwsA(isA<InvalidSecretFailure>()),
      );
    });

    test(
      'rejects an unsupported digit count before writing anything',
      () async {
        await expectLater(
          service.add(accountName: 'ada', secret: _secret(), digits: 5),
          throwsA(isA<InvalidSecretFailure>()),
        );
        expect(await secrets.accountIds(), isEmpty);
        expect(await accounts.readAll(), isEmpty);
      },
    );

    test('rejects a non-positive period before writing anything', () async {
      await expectLater(
        service.add(accountName: 'ada', secret: _secret(), period: 0),
        throwsA(isA<InvalidSecretFailure>()),
      );
      expect(await secrets.accountIds(), isEmpty);
    });

    test('rejects a negative counter for a counter-based account', () async {
      await expectLater(
        service.add(
          accountName: 'ada',
          secret: _secret(),
          type: OtpType.hotp,
          counter: -1,
        ),
        throwsA(isA<InvalidSecretFailure>()),
      );
    });
  });

  group('AccountService.delete', () {
    test('removes both the metadata and the secret', () async {
      final account = await service.add(accountName: 'ada', secret: _secret());
      await service.delete(account.id);

      expect(await accounts.findById(account.id), isNull);
      expect(await secrets.accountIds(), isEmpty);
    });

    test('removes the metadata before the secret', () async {
      // The account must disappear from the UI even if the keystore delete
      // fails, so metadata goes first and orphans are pruned later.
      final account = await service.add(accountName: 'ada', secret: _secret());
      secrets.deleteError = Exception('keystore unavailable');

      await service.delete(account.id);

      expect(await accounts.findById(account.id), isNull);
      // The secret survives the failed delete...
      expect(await secrets.accountIds(), contains(account.id));

      // ...and pruning cleans it up once the keystore is usable again.
      secrets.deleteError = null;
      expect(await service.pruneOrphanedSecrets(), contains(account.id));
      expect(await secrets.accountIds(), isEmpty);
    });

    test('does not fail when the account is already gone', () async {
      await service.delete('nonexistent');
    });
  });

  group('AccountService.update', () {
    test('changes metadata without touching the secret', () async {
      final account = await service.add(accountName: 'ada', secret: _secret());
      final before = secrets.peek(account.id);

      await service.update(account.copyWith(accountName: 'grace'));

      expect((await accounts.findById(account.id))!.accountName, 'grace');
      expect(secrets.peek(account.id), before);
      expect(
        secrets.writeLog,
        hasLength(1),
        reason: 'secret must not be rewritten',
      );
    });

    test('replaces the secret when a new one is supplied', () async {
      final account = await service.add(accountName: 'ada', secret: _secret());
      final replacement = Base32.decode('MZXW6YTBOI');

      await service.update(account, newSecret: replacement);

      expect(secrets.peek(account.id), replacement);
    });

    test('allows an update with no secret at all', () async {
      // An edit that only renames an account must not require the key again.
      final account = await service.add(accountName: 'ada', secret: _secret());
      await service.update(account.copyWith(accountName: 'grace'));
      expect((await accounts.findById(account.id))!.accountName, 'grace');
    });
  });

  group('AccountService.advanceHotpCounter', () {
    test('increments and persists the counter', () async {
      final account = await service.add(
        accountName: 'bank',
        secret: _secret(),
        type: OtpType.hotp,
        counter: 5,
      );

      final advanced = await service.advanceHotpCounter(account.id);

      expect(advanced.counter, 6);
      expect((await accounts.findById(account.id))!.counter, 6);
    });

    test('refuses to advance a time-based account', () async {
      final account = await service.add(accountName: 'ada', secret: _secret());
      await expectLater(
        service.advanceHotpCounter(account.id),
        throwsA(isA<InvalidSecretFailure>()),
      );
    });

    test(
      'reports a missing account rather than silently doing nothing',
      () async {
        await expectLater(
          service.advanceHotpCounter('nonexistent'),
          throwsA(isA<SecureStorageFailure>()),
        );
      },
    );
  });

  group('orphan handling', () {
    test('pruneOrphanedSecrets removes secrets with no account', () async {
      secrets
        ..seed('orphan-1', <int>[1, 2, 3])
        ..seed('orphan-2', <int>[4, 5, 6]);
      final kept = await service.add(accountName: 'ada', secret: _secret());

      final pruned = await service.pruneOrphanedSecrets();

      expect(pruned, containsAll(<String>['orphan-1', 'orphan-2']));
      expect(await secrets.accountIds(), <String>{kept.id});
    });

    test('pruneOrphanedSecrets is a no-op when nothing is stored', () async {
      expect(await service.pruneOrphanedSecrets(), isEmpty);
    });

    test('findAccountsMissingSecrets reports accounts with no key', () async {
      // A keystore reset leaves metadata behind; those accounts cannot generate
      // codes and must be reported rather than silently deleted.
      final account = await service.add(accountName: 'ada', secret: _secret());
      await secrets.deleteAll();

      expect(await service.findAccountsMissingSecrets(), <String>[account.id]);
    });
  });

  group('setPinned and reorder', () {
    test('pinning is persisted', () async {
      final account = await service.add(accountName: 'ada', secret: _secret());
      await service.setPinned(account.id, pinned: true);
      expect((await accounts.findById(account.id))!.pinned, isTrue);
    });

    test('reorder renumbers positions from zero', () async {
      final a = await service.add(accountName: 'a', secret: _secret());
      final b = await service.add(accountName: 'b', secret: _secret());
      final c = await service.add(accountName: 'c', secret: _secret());

      await service.reorder(<String>[c.id, a.id, b.id]);

      expect((await accounts.findById(c.id))!.sortOrder, 0);
      expect((await accounts.findById(a.id))!.sortOrder, 1);
      expect((await accounts.findById(b.id))!.sortOrder, 2);
    });

    test('a pinned account sorts before an unpinned one', () async {
      final a = await service.add(accountName: 'a', secret: _secret());
      final b = await service.add(accountName: 'b', secret: _secret());
      await service.setPinned(b.id, pinned: true);

      final ordered = await accounts.readAll();
      expect(ordered.map((x) => x.id).toList(), <String>[b.id, a.id]);
    });
  });

  group('generateAccountId', () {
    test('produces a 32-character hex string', () {
      final id = generateAccountId();
      expect(id, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });

    test('does not repeat', () {
      final ids = <String>{for (var i = 0; i < 500; i++) generateAccountId()};
      expect(ids, hasLength(500));
    });
  });

  group('Account model', () {
    test('exposes issuer as the title when present', () {
      final account = Account(
        id: '1',
        accountName: 'ada@example.com',
        issuer: 'GitHub',
      );
      expect(account.displayTitle, 'GitHub');
      expect(account.displaySubtitle, 'ada@example.com');
    });

    test('falls back to the account name when there is no issuer', () {
      final account = Account(id: '1', accountName: 'ada@example.com');
      expect(account.displayTitle, 'ada@example.com');
      // The subtitle is blank rather than repeating the title.
      expect(account.displaySubtitle, isEmpty);
    });

    test('treats an empty issuer as absent', () {
      final account = Account(id: '1', accountName: 'ada', issuer: '');
      expect(account.displayTitle, 'ada');
    });

    test('tags are unmodifiable', () {
      final account = Account(
        id: '1',
        accountName: 'ada',
        tags: const <String>['work'],
      );
      expect(() => account.tags.add('x'), throwsUnsupportedError);
    });

    test('copying the source list does not affect the account', () {
      // The constructor copies defensively, so an @immutable object's equality
      // cannot be changed from outside.
      final source = <String>['work'];
      final account = Account(id: '1', accountName: 'ada', tags: source);
      source.add('personal');
      expect(account.tags, <String>['work']);
    });

    test('equality ignores nothing that matters and includes tags', () {
      final a = Account(id: '1', accountName: 'ada', tags: const <String>['x']);
      final b = Account(id: '1', accountName: 'ada', tags: const <String>['x']);
      final c = Account(id: '1', accountName: 'ada', tags: const <String>['y']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString never includes a secret', () {
      final account = Account(
        id: '1',
        accountName: 'ada',
        algorithm: OtpAlgorithm.sha512,
      );
      expect(account.toString(), isNot(contains('secret')));
      expect(account.toString(), contains('sha512'));
    });
  });
}

/// An account repository whose metadata write always fails, for rollback tests.
class _FailingAccountRepository implements AccountRepository {
  @override
  Future<void> upsert(Account account) async {
    throw Exception('metadata write failed');
  }

  @override
  Stream<List<Account>> watchAll() => Stream.value(const <Account>[]);

  @override
  Future<List<Account>> readAll() async => const <Account>[];

  @override
  Future<Account?> findById(String id) async => null;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> reorder(List<String> orderedIds) async {}
}
