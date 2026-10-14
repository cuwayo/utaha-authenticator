import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/accounts_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Wraps [child] in the minimum app scaffolding needed to render a screen.
///
/// The screen reads its accounts and codes from providers backed by storage and
/// a timer, so both are overridden with immediate values: this suite is about
/// the screen's layout and empty states, not about storage.
Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      accountsProvider.overrideWithValue(const AsyncValue.data(<Account>[])),
      accountCodesProvider.overrideWithValue(
        const AsyncValue.data(<String, AccountCode>{}),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('AccountsScreen', () {
    testWidgets('shows the empty state when there are no accounts', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No codes yet'), findsOneWidget);
      expect(find.textContaining('Add your first account'), findsOneWidget);
    });

    testWidgets('shows the app title in the app bar', (tester) async {
      await tester.pumpWidget(_host(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Utaha Authenticator'), findsOneWidget);
    });

    testWidgets('offers a working call to action to add an account', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AccountsScreen()));
      await tester.pumpAndSettle();

      // The extended FAB opens the add-account sheet.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
    });

    testWidgets('the add-account sheet offers both add flows', (tester) async {
      await tester.pumpWidget(_host(const AccountsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Scan a QR code'), findsOneWidget);
      expect(find.text('Enter a key manually'), findsOneWidget);
    });

    testWidgets('renders without overflow on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with a large text scale without overflowing', (
      tester,
    ) async {
      // Accessibility requirement: the layout must survive large font scaling.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _host(const AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No codes yet'), findsOneWidget);
    });
  });
}
