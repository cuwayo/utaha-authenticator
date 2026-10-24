import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/app.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_settings_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';

/// Boots the real application widget with the database swapped for an in-memory
/// repository.
///
/// This host has no Android emulator, so this test is the closest available
/// substitute for launching the app: it exercises the router, the theme, the
/// localisation delegates and the shell together, which a per-screen test
/// cannot do.
Widget _bootApp({
  // Onboarding is a separate concern with its own tests; these boot tests are
  // about the shell, so they start past it.
  AppSettings settings = const AppSettings(onboardingCompleted: true),
}) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(settings),
      ),
      // The real repositories need SQLite and the platform keystore, neither of
      // which exists in a widget test. These fakes keep the app's own wiring
      // (router, theme, providers) under test while replacing only storage.
      accountRepositoryProvider.overrideWithValue(InMemoryAccountRepository()),
      secretRepositoryProvider.overrideWithValue(InMemorySecretRepository()),
      // These two feed the account list from storage on a timer. Overridden with
      // immediate values so this test exercises the app shell without waiting on
      // a database or a tick.
      accountsProvider.overrideWithValue(const AsyncValue.data(<Account>[])),
      // The code stream ticks on a timer forever; overriding it keeps the test
      // from finishing with pending timers.
      accountCodesProvider.overrideWithValue(
        const AsyncValue.data(<String, AccountCode>{}),
      ),
    ],
    child: const UtahaApp(),
  );
}

void main() {
  testWidgets('app boots to the accounts screen', (tester) async {
    await tester.pumpWidget(_bootApp());
    await tester.pumpAndSettle();

    // The accounts branch is the initial location, so the empty state is shown.
    expect(find.text('Utaha Authenticator'), findsOneWidget);
    expect(find.text('No codes yet'), findsOneWidget);
    // Both top-level destinations are reachable from the navigation bar.
    expect(find.text('Codes'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('navigating to settings shows the settings controls', (
    tester,
  ) async {
    await tester.pumpWidget(_bootApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // A representative control from each settings group. "Codes" is avoided
    // here because it is also a navigation bar label.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Hide codes until tapped'), findsOneWidget);

    // The settings list is lazy, so lower groups must be scrolled into view
    // before they exist in the tree.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Digit grouping'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Digit grouping'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('List spacing'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('List spacing'), findsOneWidget);
  });

  testWidgets('dark mode from stored settings is applied at boot', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bootApp(settings: const AppSettings(themeMode: AppThemeMode.dark)),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('AMOLED setting produces a true black scaffold', (tester) async {
    await tester.pumpWidget(
      _bootApp(
        settings: const AppSettings(
          themeMode: AppThemeMode.dark,
          useAmoled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xFF000000));
  });

  testWidgets(
    'stored accent colour reaches the theme when dynamic colour is off',
    (tester) async {
      const seedColorValue = 0xFF00695C;
      await tester.pumpWidget(
        _bootApp(
          settings: const AppSettings(
            useDynamicColor: false,
            seedColorValue: seedColorValue,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      final expected = ColorScheme.fromSeed(
        seedColor: const Color(seedColorValue),
      );
      expect(Theme.of(context).colorScheme.primary, expected.primary);
    },
  );

  testWidgets('toggling a setting persists it through the repository', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository(
      const AppSettings(onboardingCompleted: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(),
          ),
          secretRepositoryProvider.overrideWithValue(
            InMemorySecretRepository(),
          ),
          accountsProvider.overrideWithValue(
            const AsyncValue.data(<Account>[]),
          ),
          accountCodesProvider.overrideWithValue(
            const AsyncValue.data(<String, AccountCode>{}),
          ),
        ],
        child: const UtahaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide codes until tapped'));
    await tester.pumpAndSettle();

    // The change must reach storage, not just the widget tree.
    expect((await repository.load()).tapToReveal, isTrue);
  });

  testWidgets('compact density from stored settings reaches the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bootApp(settings: const AppSettings(listDensity: ListDensity.compact)),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).visualDensity, VisualDensity.compact);
  });
}
