import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_settings_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';

const String _secret = 'JBSWY3DPEHPK3PXP';

/// A fixed instant so generated codes are deterministic.
final DateTime _fixedNow = DateTime.fromMillisecondsSinceEpoch(
  1111111109 * 1000,
  isUtc: true,
);

void main() {
  late InMemoryAccountRepository accounts;
  late InMemorySecretRepository secrets;

  ProviderContainer makeContainer() {
    accounts = InMemoryAccountRepository();
    secrets = InMemorySecretRepository();
    final container = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        secretRepositoryProvider.overrideWithValue(secrets),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(),
        ),
        clockProvider.overrideWithValue(FixedClock(_fixedNow)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Waits for [stream] to emit its first value.
  ///
  /// Providers are driven by the container here rather than by a widget, so
  /// this polls the container's state instead of awaiting a provider `future` —
  /// which does not resolve for these provider types.
  /// Polls [read] until it produces a value.
  ///
  /// Takes a closure rather than a provider so it needs no provider type name,
  /// which this Riverpod version does not export.
  ///
  /// The caller must keep a subscription open — see [keepAlive] — because a
  /// stream provider does not run until something listens to it.
  /// Polls [read] until it produces a value satisfying [until].
  ///
  /// A predicate rather than a bare null check, because the code stream
  /// legitimately emits an empty map before the account list has loaded — so
  /// "has any value" is not the same as "is ready".
  Future<T> firstValue<T>(
    T? Function() read, {
    bool Function(T value)? until,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = read();
      if (value != null && (until == null || until(value))) return value;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('provider did not produce a value within $timeout');
  }

  group('account list wiring', () {
    test('accounts stream emits the stored accounts', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: Base32.decode(_secret),
      );

      final list = await firstValue(
        () => container.read(accountsProvider).value,
      );

      expect(list, hasLength(1));
      expect(list.single.issuer, 'GitHub');
    });

    test('accounts stream starts empty rather than never emitting', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final list = await firstValue(
        () => container.read(accountsProvider).value,
      );
      expect(list, isEmpty);
    });
  });

  group('code generation wiring', () {
    test('codes are produced for a stored account', () async {
      // This is the end-to-end path the whole app depends on: a stored secret
      // must turn into a code on screen. It is asserted here because the
      // provider wiring is where it can silently break — an earlier version
      // awaited a provider `future` that never resolved, leaving the list
      // permanently empty of codes.
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      final account = await service.add(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: Base32.decode(_secret),
      );

      final codes = await firstValue(
        () => container.read(accountCodesProvider).value,
        until: (value) => value.isNotEmpty,
      );

      expect(codes, contains(account.id));
      final code = codes[account.id]!;
      expect(code.code, hasLength(6));
      expect(int.tryParse(code.code), isNotNull);
      // The RFC 6238 vectors use a different secret, so the exact value is not
      // asserted here; the next test cross-checks this code against one derived
      // directly from the stored secret, which is the property that matters.
      expect(code.code, isNot('000000'));
    });

    test('the code matches one generated directly from the secret', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(accountName: 'ada', secret: Base32.decode(_secret));

      final codes = await firstValue(
        () => container.read(accountCodesProvider).value,
        until: (value) => value.isNotEmpty,
      );

      final generator = CodeGenerator(
        secrets: secrets,
        clock: FixedClock(_fixedNow),
      );
      final stored = await accounts.readAll();
      final expected = await generator.generate(stored.single);

      expect(codes[stored.single.id]!.code, expected!.code);
    });

    test('the countdown is populated for time-based accounts', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(accountName: 'ada', secret: Base32.decode(_secret));

      final codes = await firstValue(
        () => container.read(accountCodesProvider).value,
        until: (value) => value.isNotEmpty,
      );
      final code = codes.values.single;

      expect(code.secondsRemaining, isNotNull);
      expect(code.progress, isNotNull);
      expect(code.secondsRemaining, inInclusiveRange(1, 30));
    });

    test(
      'an account with no secret is omitted rather than breaking the list',
      () async {
        final container = makeContainer();
        // Stream providers do not run until something listens; widgets do this
        // implicitly via ref.watch, so a container-based test must do it here.
        addTearDown(container.listen(accountsProvider, (_, _) {}).close);
        addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
        final service = AccountService(accounts: accounts, secrets: secrets);
        await service.add(accountName: 'ada', secret: Base32.decode(_secret));
        // Simulate a keystore reset.
        await secrets.deleteAll();

        // With no usable secret the map stays empty; give the stream time to
        // reach that state rather than accepting the pre-load empty map.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final codes =
            container.read(accountCodesProvider).value ??
            const <String, AccountCode>{};
        expect(codes, isEmpty);
      },
    );

    test('codes update when a new account is added', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(accountName: 'first', secret: Base32.decode(_secret));

      final initial = await firstValue(
        () => container.read(accountCodesProvider).value,
        until: (value) => value.isNotEmpty,
      );
      expect(initial, hasLength(1));

      await service.add(accountName: 'second', secret: Base32.decode(_secret));

      // The stream restarts when the account list changes.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        final codes = container.read(accountCodesProvider).value;
        if (codes != null && codes.length == 2) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('codes did not pick up the second account');
    });
  });

  group('search wiring', () {
    test('the query filters the visible accounts', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        secret: Base32.decode(_secret),
      );
      await service.add(
        accountName: 'grace@example.com',
        issuer: 'GitLab',
        secret: Base32.decode(_secret),
      );
      await firstValue(() => container.read(accountsProvider).value);

      container.read(accountSearchQueryProvider.notifier).query = 'github';
      // Let the derived provider recompute.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final visible = container.read(visibleAccountsProvider);
      expect(visible, hasLength(1));
      expect(visible.single.issuer, 'GitHub');
    });

    test('an empty query shows everything', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      await service.add(accountName: 'a', secret: Base32.decode(_secret));
      await service.add(accountName: 'b', secret: Base32.decode(_secret));
      await firstValue(() => container.read(accountsProvider).value);

      expect(container.read(visibleAccountsProvider), hasLength(2));
    });

    test('a pending deletion is hidden from the list', () async {
      final container = makeContainer();
      // Stream providers do not run until something listens; widgets do this
      // implicitly via ref.watch, so a container-based test must do it here.
      addTearDown(container.listen(accountsProvider, (_, _) {}).close);
      addTearDown(container.listen(accountCodesProvider, (_, _) {}).close);
      final service = AccountService(accounts: accounts, secrets: secrets);
      final account = await service.add(
        accountName: 'ada',
        secret: Base32.decode(_secret),
      );
      await firstValue(() => container.read(accountsProvider).value);

      container.read(pendingDeletionsProvider.notifier).schedule(account.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(visibleAccountsProvider), isEmpty);
    });
  });
}
