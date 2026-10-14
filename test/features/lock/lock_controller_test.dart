import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/platform/biometric_auth.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_settings_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/features/lock/presentation/lock_controller.dart';

void main() {
  late InMemorySettingsRepository settings;
  late FakeBiometricAuth auth;

  /// Builds a container with the given settings.
  ProviderContainer makeContainer([
    AppSettings initial = AppSettings.defaults,
  ]) {
    settings = InMemorySettingsRepository(initial);
    auth = FakeBiometricAuth();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        biometricAuthProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(
          InMemoryAccountRepository(),
        ),
        secretRepositoryProvider.overrideWithValue(InMemorySecretRepository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Waits for the settings stream to deliver its first value.
  ///
  /// `settingsControllerProvider.future` does not resolve for this provider
  /// type, so the value is polled instead: the repository's stream emits on a
  /// microtask, which a short delay allows to complete.
  Future<void> settle(ProviderContainer container) async {
    // A subscription is required to keep the provider alive: `read` alone does
    // not hold the underlying stream open, so the first value never arrives.
    final subscription = container.listen(
      settingsControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    for (var attempt = 0; attempt < 50; attempt++) {
      if (container.read(settingsControllerProvider).value != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('settings did not load');
  }

  group('when the lock is switched off', () {
    test('the state is disabled, not locked', () async {
      final container = makeContainer();
      await settle(container);
      expect(container.read(lockControllerProvider), isA<LockDisabled>());
    });

    test('isUnlocked reports true, so nothing blocks the UI', () async {
      final container = makeContainer();
      await settle(container);
      expect(container.read(lockControllerProvider).isUnlocked, isTrue);
    });

    test('lockNow does nothing', () async {
      final container = makeContainer();
      await settle(container);
      container.read(lockControllerProvider.notifier).lockNow();
      expect(container.read(lockControllerProvider), isA<LockDisabled>());
    });

    test('unlock succeeds without prompting', () async {
      final container = makeContainer();
      await settle(container);
      final ok = await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'test');
      expect(ok, isTrue);
      expect(auth.authenticateCount, 0);
    });
  });

  group('when the lock is switched on', () {
    test('the app starts locked', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);

      final state = container.read(lockControllerProvider);
      expect(state, isA<Locked>());
      expect((state as Locked).reason, LockReason.launch);
    });

    test('isUnlocked reports false, so the UI is covered', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      expect(container.read(lockControllerProvider).isUnlocked, isFalse);
    });

    test('unlocking prompts and then succeeds', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);

      final ok = await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'please unlock');

      expect(ok, isTrue);
      expect(auth.authenticateCount, 1);
      expect(auth.reasons.single, 'please unlock');
      expect(container.read(lockControllerProvider), isA<Unlocked>());
    });

    test('a cancelled prompt leaves the app locked', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      auth.succeeds = false;

      final ok = await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'test');

      expect(ok, isFalse);
      expect(container.read(lockControllerProvider), isA<Locked>());
    });

    test('the user can retry after a cancelled prompt', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);

      auth.succeeds = false;
      await container.read(lockControllerProvider.notifier).unlock(reason: 'a');

      auth.succeeds = true;
      final ok = await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'b');

      expect(ok, isTrue);
      expect(container.read(lockControllerProvider), isA<Unlocked>());
    });

    test('lockNow locks an unlocked app', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');
      expect(container.read(lockControllerProvider), isA<Unlocked>());

      container.read(lockControllerProvider.notifier).lockNow();

      final state = container.read(lockControllerProvider);
      expect(state, isA<Locked>());
      expect((state as Locked).reason, LockReason.manual);
    });
  });

  group('turning the lock on and off', () {
    test('enabling it locks the app immediately', () async {
      final container = makeContainer();
      await settle(container);
      expect(container.read(lockControllerProvider), isA<LockDisabled>());

      await container
          .read(settingsControllerProvider.notifier)
          .mutate((current) => current.copyWith(appLockEnabled: true));
      await settle(container);

      expect(container.read(lockControllerProvider), isA<Locked>());
    });

    test('disabling it unlocks the app immediately', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      expect(container.read(lockControllerProvider), isA<Locked>());

      await container
          .read(settingsControllerProvider.notifier)
          .mutate((current) => current.copyWith(appLockEnabled: false));
      await settle(container);

      expect(container.read(lockControllerProvider), isA<LockDisabled>());
    });

    test('changing an unrelated setting does NOT re-lock the app', () async {
      // Regression test. Watching the whole settings object would rebuild the
      // lock controller whenever anything changed, so toggling dark mode or
      // list density would lock the user out mid-session.
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');
      expect(container.read(lockControllerProvider), isA<Unlocked>());

      await container
          .read(settingsControllerProvider.notifier)
          .mutate(
            (current) => current.copyWith(
              themeMode: AppThemeMode.dark,
              useAmoled: true,
              tapToReveal: true,
            ),
          );
      await settle(container);

      expect(
        container.read(lockControllerProvider),
        isA<Unlocked>(),
        reason: 'an unrelated settings change must not lock the app',
      );
    });
  });

  group('timeout', () {
    /// Backgrounds, waits, then foregrounds.
    Future<void> backgroundAndReturn(
      ProviderContainer container, {
      required Duration away,
    }) async {
      // The controller compares against the wall clock, so the elapsed time is
      // simulated by moving the recorded instant back rather than sleeping.
      container.read(lockControllerProvider.notifier)
        ..didEnterBackground()
        ..debugBackgroundedAt = DateTime.now().subtract(away)
        ..didReturnToForeground();
    }

    test('a short absence does not lock', () async {
      final container = makeContainer(
        const AppSettings(appLockEnabled: true, lockTimeoutSeconds: 60),
      );
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');

      await backgroundAndReturn(container, away: const Duration(seconds: 5));

      expect(container.read(lockControllerProvider), isA<Unlocked>());
    });

    test('a long absence locks', () async {
      final container = makeContainer(
        const AppSettings(appLockEnabled: true, lockTimeoutSeconds: 60),
      );
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');

      await backgroundAndReturn(container, away: const Duration(seconds: 61));

      final state = container.read(lockControllerProvider);
      expect(state, isA<Locked>());
      expect((state as Locked).reason, LockReason.timeout);
    });

    test('a timeout of zero locks as soon as the app is left', () async {
      final container = makeContainer(
        const AppSettings(appLockEnabled: true, lockTimeoutSeconds: 0),
      );
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');

      await backgroundAndReturn(container, away: Duration.zero);

      expect(container.read(lockControllerProvider), isA<Locked>());
    });

    test('exactly the timeout locks', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');

      await backgroundAndReturn(container, away: const Duration(seconds: 30));

      expect(container.read(lockControllerProvider), isA<Locked>());
    });

    test('returning without having backgrounded does not lock', () async {
      final container = makeContainer(
        const AppSettings(appLockEnabled: true, lockTimeoutSeconds: 0),
      );
      await settle(container);
      await container.read(lockControllerProvider.notifier).unlock(reason: 'x');

      // No didEnterBackground first.
      container.read(lockControllerProvider.notifier).didReturnToForeground();

      expect(container.read(lockControllerProvider), isA<Unlocked>());
    });

    test(
      'returning to an already-locked app does not change the reason',
      () async {
        final container = makeContainer(
          const AppSettings(appLockEnabled: true),
        );
        await settle(container);
        final before = container.read(lockControllerProvider) as Locked;

        container.read(lockControllerProvider.notifier).didReturnToForeground();

        final after = container.read(lockControllerProvider) as Locked;
        expect(after.reason, before.reason);
      },
    );
  });

  group('concurrent prompts', () {
    test(
      'a second unlock while one is running does not start another',
      () async {
        final container = makeContainer(
          const AppSettings(appLockEnabled: true),
        );
        await settle(container);
        final lock = container.read(lockControllerProvider.notifier);

        // Start two without awaiting the first.
        final first = lock.unlock(reason: 'one');
        final second = lock.unlock(reason: 'two');

        await Future.wait(<Future<bool>>[first, second]);

        expect(
          auth.authenticateCount,
          1,
          reason: 'only one prompt should have been shown',
        );
      },
    );

    test('authenticating is flagged while a prompt is up', () async {
      final container = makeContainer(const AppSettings(appLockEnabled: true));
      await settle(container);
      final lock = container.read(lockControllerProvider.notifier);

      final pending = lock.unlock(reason: 'x');
      // The state is set before the prompt resolves.
      final during = container.read(lockControllerProvider);
      expect(during, isA<Locked>());
      expect((during as Locked).authenticating, isTrue);

      await pending;
      expect(container.read(lockControllerProvider), isA<Unlocked>());
    });
  });

  group('platform failure', () {
    test(
      'a throwing authenticator leaves the app locked, not crashed',
      () async {
        final container = makeContainer(
          const AppSettings(appLockEnabled: true),
        );
        await settle(container);
        auth.failWith = Exception('platform channel died');

        final ok = await container
            .read(lockControllerProvider.notifier)
            .unlock(reason: 'x');

        expect(ok, isFalse);
        expect(container.read(lockControllerProvider), isA<Locked>());
      },
    );
  });
}
