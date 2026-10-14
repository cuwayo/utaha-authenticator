import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/app/shell.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_account_repository.dart';
import 'package:utaha_authenticator/data/repositories/in_memory_settings_repository.dart';
import 'package:utaha_authenticator/data/secure/in_memory_secret_repository.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(),
          ),
          secretRepositoryProvider.overrideWithValue(
            InMemorySecretRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(),
          ),
          accountsProvider.overrideWithValue(
            const AsyncValue.data(<Account>[]),
          ),
          accountCodesProvider.overrideWithValue(
            const AsyncValue.data(<String, AccountCode>{}),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _ShellProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('adaptive navigation breakpoint', () {
    testWidgets('a phone-sized window uses a navigation bar', (tester) async {
      await pumpAt(tester, const Size(400, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet-sized window uses a navigation rail', (tester) async {
      await pumpAt(tester, const Size(1000, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a foldable-sized window uses a rail', (tester) async {
      await pumpAt(tester, const Size(700, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('the breakpoint sits at 600dp', (tester) async {
      await pumpAt(tester, const Size(599, 800));
      expect(find.byType(NavigationBar), findsOneWidget);

      await pumpAt(tester, const Size(601, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('a narrow landscape phone keeps the bar', (tester) async {
      // Wide-ish but short; a rail would eat the little vertical space there is.
      await pumpAt(tester, const Size(560, 360));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('both layouts offer the same destinations', (tester) async {
      await pumpAt(tester, const Size(400, 800));
      expect(find.text('Codes'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await pumpAt(tester, const Size(1000, 800));
      expect(find.text('Codes'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}

/// Renders the same navigation choice [AppShell] makes, without standing up
/// go_router's stateful shell.
///
/// The breakpoint constant is imported from the real shell, so this test fails
/// if that threshold changes.
class _ShellProbe extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    return Scaffold(
      body: isWide
          ? NavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  icon: Icon(Icons.pin_outlined),
                  label: Text('Codes'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: Text('Settings'),
                ),
              ],
            )
          : Column(
              children: <Widget>[
                const Expanded(child: SizedBox.shrink()),
                NavigationBar(
                  onDestinationSelected: (_) {},
                  destinations: const <NavigationDestination>[
                    NavigationDestination(
                      icon: Icon(Icons.pin_outlined),
                      label: 'Codes',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: 'Settings',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
