import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_settings_repository.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/account_tile.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/countdown_indicator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/issuer_avatar.dart';
import 'package:utaha_authenticator/features/onboarding/presentation/onboarding_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Builds a tile with sensible defaults so each test only states what it cares
/// about.
Widget hostTile({
  required Account account,
  AccountCode? code,
  CodeGrouping grouping = CodeGrouping.triples,
  bool tapToReveal = false,
  bool compact = false,
  VoidCallback? onCopy,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AccountTile(
          account: account,
          code: code,
          grouping: grouping,
          tapToReveal: tapToReveal,
          compact: compact,
          onCopy: onCopy ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('onboarding', () {
    /// The gate needs settings; this builds one at a chosen state.
    Widget hostGate({required bool completed}) {
      return ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              AppSettings(onboardingCompleted: completed),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingGate(child: Scaffold(body: Text('the app'))),
        ),
      );
    }

    testWidgets('shows the introduction on a fresh install', (tester) async {
      await tester.pumpWidget(hostGate(completed: false));
      await tester.pumpAndSettle();

      expect(find.text('Your codes stay on this device'), findsOneWidget);
      expect(find.text('the app'), findsNothing);
    });

    testWidgets('goes straight to the app once dismissed', (tester) async {
      await tester.pumpWidget(hostGate(completed: true));
      await tester.pumpAndSettle();

      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Your codes stay on this device'), findsNothing);
    });

    testWidgets('is skippable from the first page', (tester) async {
      await tester.pumpWidget(hostGate(completed: false));
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('has exactly three pages', (tester) async {
      // The brief caps onboarding at three screens.
      await tester.pumpWidget(hostGate(completed: false));
      await tester.pumpAndSettle();

      expect(find.text('Your codes stay on this device'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add an account in seconds'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Keep a backup somewhere safe'), findsOneWidget);
      // The last page offers the finish action instead of Next.
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('the last page finishes the flow', (tester) async {
      await tester.pumpWidget(hostGate(completed: false));
      await tester.pumpAndSettle();

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      // The gate rebuilds into the app once the flag is stored.
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('renders without overflow at a large text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: hostGate(completed: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('account tile accessibility', () {
    final account = Account(
      id: 'a1',
      accountName: 'ada@example.com',
      issuer: 'GitHub',
    );

    testWidgets('announces the row as a single label', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 12,
            progress: 0.6,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(AccountTile));
      final label = semantics.label;
      // Issuer, account, the code and the countdown, in one announcement.
      expect(label, contains('GitHub'));
      expect(label, contains('ada@example.com'));
      expect(label, contains('1 2 3 4 5 6'));
      expect(label, contains('12 seconds left'));
    });

    testWidgets('spells the code out digit by digit', (tester) async {
      // A screen reader must not read "123456" as "one hundred twenty-three
      // thousand four hundred fifty-six".
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(AccountTile)).label,
        contains('1 2 3 4 5 6'),
      );
    });

    testWidgets('does not announce the code when tap-to-reveal is on', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
          tapToReveal: true,
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(AccountTile)).label;
      expect(label, contains('hidden'));
      expect(label, isNot(contains('1 2 3 4 5 6')));
    });

    testWidgets('announces a missing secret instead of staying silent', (
      tester,
    ) async {
      await tester.pumpWidget(hostTile(account: account));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(AccountTile)).label,
        contains('Key missing'),
      );
    });

    testWidgets('marks the row as a button when it can be copied', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(AccountTile)).flagsCollection.isButton,
        isTrue,
      );
    });

    testWidgets('the countdown ring is announced as a number of seconds', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CountdownIndicator(
              progress: 0.5,
              secondsRemaining: 15,
              isExpiringSoon: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(CountdownIndicator)).label,
        contains('15 seconds'),
      );
    });
  });

  group('tap-to-reveal actually hides the code', () {
    // Regression tests for a bug where the setting did nothing: the tile
    // rendered the real digits and merely added a "hidden" icon beside them.
    // The earlier test only checked the *announcement*, so it passed while the
    // code was plainly visible on screen.
    final account = Account(
      id: 'a1',
      accountName: 'ada@example.com',
      issuer: 'GitHub',
    );

    AccountCode codeOf(String value) =>
        AccountCode(code: value, secondsRemaining: 20, progress: 0.3);

    testWidgets('the digits are not rendered while hidden', (tester) async {
      await tester.pumpWidget(
        hostTile(account: account, code: codeOf('123456'), tapToReveal: true),
      );
      await tester.pumpAndSettle();

      // Neither the raw nor the grouped form may appear anywhere in the tree.
      expect(find.text('123456'), findsNothing);
      expect(find.text('123 456'), findsNothing);
      expect(find.textContaining('123'), findsNothing);
    });

    testWidgets('a placeholder is shown instead', (tester) async {
      await tester.pumpWidget(
        hostTile(account: account, code: codeOf('123456'), tapToReveal: true),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('•'), findsOneWidget);
    });

    testWidgets('the placeholder matches the digit count', (tester) async {
      // So the row does not change width when revealed.
      for (final entry in <String, int>{
        '123456': 6,
        '1234567': 7,
        '12345678': 8,
      }.entries) {
        await tester.pumpWidget(
          hostTile(
            account: account,
            code: codeOf(entry.key),
            tapToReveal: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('•' * entry.value),
          findsOneWidget,
          reason: '${entry.value} digits',
        );
      }
    });

    testWidgets('tapping once reveals without copying', (tester) async {
      var copied = 0;
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: codeOf('123456'),
          tapToReveal: true,
          onCopy: () => copied++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AccountTile));
      await tester.pumpAndSettle();

      expect(find.text('123 456'), findsOneWidget);
      expect(copied, 0, reason: 'the first tap reveals, it does not copy');
    });

    testWidgets('tapping again copies', (tester) async {
      var copied = 0;
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: codeOf('123456'),
          tapToReveal: true,
          onCopy: () => copied++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AccountTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AccountTile));
      await tester.pumpAndSettle();

      expect(copied, 1);
    });

    testWidgets('the code hides again when it changes', (tester) async {
      // A revealed code must not stay revealed into the next code, or the
      // setting would quietly stop protecting anything.
      Widget build(String code) =>
          hostTile(account: account, code: codeOf(code), tapToReveal: true);

      await tester.pumpWidget(build('111111'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AccountTile));
      await tester.pumpAndSettle();
      expect(find.text('111 111'), findsOneWidget);

      await tester.pumpWidget(build('222222'));
      await tester.pumpAndSettle();

      expect(find.text('222 222'), findsNothing);
      expect(find.textContaining('•'), findsOneWidget);
    });

    testWidgets('the hidden code is announced as hidden, not read out', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostTile(account: account, code: codeOf('123456'), tapToReveal: true),
      );
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(AccountTile)).label;
      expect(label, contains('hidden'));
      expect(label, isNot(contains('1 2 3 4 5 6')));
    });

    testWidgets('with the setting off the code is visible and copies at once', (
      tester,
    ) async {
      var copied = 0;
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: codeOf('123456'),
          onCopy: () => copied++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('123 456'), findsOneWidget);
      await tester.tap(find.byType(AccountTile));
      await tester.pumpAndSettle();
      expect(copied, 1, reason: 'no reveal step when the setting is off');
    });
  });

  group('code grouping reaches the tile', () {
    final account = Account(id: 'a1', accountName: 'ada', issuer: 'GitHub');

    testWidgets('groups in threes by default', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('123 456'), findsOneWidget);
    });

    testWidgets('honours a pairs preference', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
          grouping: CodeGrouping.pairs,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 34 56'), findsOneWidget);
    });

    testWidgets('honours no grouping', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
          grouping: CodeGrouping.none,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('123456'), findsOneWidget);
    });
  });

  group('expiring codes use the error colour', () {
    final account = Account(id: 'a1', accountName: 'ada', issuer: 'GitHub');

    testWidgets('the countdown turns red in the last five seconds', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 3,
            progress: 0.9,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = tester.widget<CountdownIndicator>(
        find.byType(CountdownIndicator),
      );
      expect(indicator.isExpiringSoon, isTrue);
    });

    testWidgets('a code with more than five seconds left is not flagged', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostTile(
          account: account,
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 6,
            progress: 0.8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = tester.widget<CountdownIndicator>(
        find.byType(CountdownIndicator),
      );
      expect(indicator.isExpiringSoon, isFalse);
    });
  });

  group('issuer avatar', () {
    testWidgets('shows the first letter, uppercased', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IssuerAvatar(label: 'github')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('G'), findsOneWidget);
    });

    testWidgets('the same label always gets the same colour', (tester) async {
      // Object.hashCode is randomised per process, so deriving the colour from
      // it would make avatars change colour on every restart.
      final colours = <Color>[];
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: IssuerAvatar(label: 'GitHub')),
          ),
        );
        await tester.pumpAndSettle();
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(IssuerAvatar),
            matching: find.byType(Container),
          ),
        );
        colours.add((container.decoration! as BoxDecoration).color!);
      }
      expect(colours.toSet(), hasLength(1));
    });

    testWidgets('an empty label falls back to a question mark', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: IssuerAvatar(label: '')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('touch targets', () {
    testWidgets('an account row is at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: Account(id: 'a1', accountName: 'ada', issuer: 'GitHub'),
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(AccountTile));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a compact row is still at least 48dp tall', (tester) async {
      await tester.pumpWidget(
        hostTile(
          account: Account(id: 'a1', accountName: 'ada', issuer: 'GitHub'),
          code: const AccountCode(
            code: '123456',
            secondsRemaining: 20,
            progress: 0.3,
          ),
          compact: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(AccountTile)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
