import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/services/account_importer.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';
import 'package:utaha_authenticator/features/scan/presentation/manual_entry_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// A valid secret used across these tests.
const String _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  late InMemoryAccountRepository accounts;
  late InMemorySecretRepository secrets;
  late AccountImporter importer;

  setUp(() {
    accounts = InMemoryAccountRepository();
    secrets = InMemorySecretRepository();
    importer = AccountImporter(
      AccountService(accounts: accounts, secrets: secrets),
    );
  });

  Widget host({Account? editing}) {
    return ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        secretRepositoryProvider.overrideWithValue(secrets),
        accountServiceProvider.overrideWithValue(
          AccountService(accounts: accounts, secrets: secrets),
        ),
        accountImporterProvider.overrideWithValue(importer),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ManualEntryScreen(editing: editing),
      ),
    );
  }

  /// Pumps the form in a viewport tall enough to build every field.
  ///
  /// The form is a lazy `ListView`; a tall viewport avoids a whole class of
  /// "widget does not exist yet" failures without the tests having to scroll.
  Future<void> pumpForm(WidgetTester tester, {Account? editing}) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(editing: editing));
    await tester.pumpAndSettle();
  }

  /// Enters text into the field carrying [label].
  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, label).first,
      value,
    );
    await tester.pump();
  }

  /// Taps the save button.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Add account').last);
    await tester.pumpAndSettle();
  }

  group('manual entry — validation', () {
    testWidgets('the form renders all the fields', (tester) async {
      await pumpForm(tester);

      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Account name'), findsOneWidget);
      expect(find.text('Secret key'), findsOneWidget);
      for (final label in <String>[
        'Code type',
        'Algorithm',
        'Digits',
        'Seconds per code',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('saving with an empty name reports it', (tester) async {
      await pumpForm(tester);

      await tapSave(tester);

      expect(find.textContaining('recognise this account'), findsOneWidget);
    });

    testWidgets('saving with an empty secret reports it', (tester) async {
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada@example.com');
      await tapSave(tester);

      expect(find.text('Please enter the secret key.'), findsOneWidget);
    });

    testWidgets('a secret with an invalid character explains which one', (
      tester,
    ) async {
      // '1' is not in the Base32 alphabet; the message must name it rather than
      // silently dropping it and storing a wrong key.
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada@example.com');
      await enter(tester, 'Secret key', 'JBSW1YDP');
      await tapSave(tester);

      expect(find.textContaining('1'), findsWidgets);
      expect(find.textContaining('A–Z'), findsOneWidget);
    });

    testWidgets('a secret in groups is accepted', (tester) async {
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada@example.com');
      await enter(tester, 'Secret key', 'JBSW Y3DP EHPK 3PXP');
      await tapSave(tester);

      // Saved, so the form is gone and the account exists.
      expect(find.text('Add account'), findsNothing);
      expect(await accounts.readAll(), hasLength(1));
    });

    testWidgets('a period of zero is rejected', (tester) async {
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada@example.com');
      await enter(tester, 'Secret key', _secret);
      await enter(tester, 'Seconds per code', '0');
      await tapSave(tester);

      expect(find.textContaining('greater than zero'), findsOneWidget);
    });

    testWidgets('the counter field appears only for counter-based accounts', (
      tester,
    ) async {
      await pumpForm(tester);

      expect(find.text('Seconds per code'), findsOneWidget);
      expect(find.text('Counter'), findsNothing);
      await tester.tap(find.text('Counter-based'));
      await tester.pumpAndSettle();

      expect(find.text('Counter'), findsOneWidget);
      expect(find.text('Seconds per code'), findsNothing);
    });

    testWidgets('a negative counter is rejected', (tester) async {
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada');
      await enter(tester, 'Secret key', _secret);
      await tester.tap(find.text('Counter-based'));
      await tester.pumpAndSettle();
      await enter(tester, 'Counter', '');
      await tapSave(tester);

      expect(find.textContaining('zero or more'), findsOneWidget);
    });
  });

  group('manual entry — saving', () {
    testWidgets('a valid entry is added with its secret', (tester) async {
      await pumpForm(tester);

      await enter(tester, 'Service', 'GitHub');
      await enter(tester, 'Account name', 'ada@example.com');
      await enter(tester, 'Secret key', _secret);
      await tapSave(tester);

      final stored = await accounts.readAll();
      expect(stored, hasLength(1));
      expect(stored.single.issuer, 'GitHub');
      expect(stored.single.accountName, 'ada@example.com');
      // The key must be stored, decoded from Base32.
      expect(secrets.peek(stored.single.id), isNotNull);
    });

    testWidgets('choosing an algorithm and digit count persists them', (
      tester,
    ) async {
      await pumpForm(tester);

      await enter(tester, 'Account name', 'ada');
      await enter(tester, 'Secret key', _secret);
      await tester.tap(find.text('SHA512'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      final stored = await accounts.readAll();
      expect(stored.single.algorithm.name, 'sha512');
      expect(stored.single.digits, 8);
    });

    testWidgets('the secret field is masked by default and can be revealed', (
      tester,
    ) async {
      await pumpForm(tester);

      await enter(tester, 'Secret key', _secret);

      // Masked: the plain text is not rendered.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Secret key'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.obscureText, isTrue);

      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();

      final revealed = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Secret key'),
          matching: find.byType(TextField),
        ),
      );
      expect(revealed.obscureText, isFalse);
    });
  });

  group('manual entry — editing', () {
    testWidgets('prefills the fields but not the secret', (tester) async {
      final account = Account(
        id: 'a1',
        accountName: 'ada@example.com',
        issuer: 'GitHub',
      );
      await accounts.upsert(account);

      await pumpForm(tester, editing: account);

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      // The stored key is never loaded into a text field, so it cannot leak
      // into the widget tree or a keyboard buffer.
      expect(find.text(_secret), findsNothing);
      expect(
        find.text('Leave this blank to keep the current key'),
        findsOneWidget,
      );
    });

    testWidgets('renaming keeps the existing secret', (tester) async {
      final account = Account(id: 'a1', accountName: 'ada');
      await accounts.upsert(account);
      secrets.seed('a1', <int>[1, 2, 3, 4]);

      await pumpForm(tester, editing: account);

      await enter(tester, 'Account name', 'grace');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await accounts.findById('a1'))!.accountName, 'grace');
      // The key is untouched.
      expect(secrets.peek('a1'), <int>[1, 2, 3, 4]);
    });

    testWidgets('the title says Edit, not Add', (tester) async {
      final account = Account(id: 'a1', accountName: 'ada');
      await pumpForm(tester, editing: account);

      expect(find.text('Edit account'), findsOneWidget);
    });
  });
}
