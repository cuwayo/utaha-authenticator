import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Width at or above which the app switches to a navigation rail.
///
/// 600dp is Material's breakpoint between "compact" and "medium" window sizes,
/// which covers large phones in landscape, foldables and tablets.
const double kWideLayoutBreakpoint = 600;

/// Hosts the two top-level destinations and adapts its navigation to the
/// available width.
class AppShell extends StatelessWidget {
  /// Creates the shell around [navigationShell].
  const new({required this.navigationShell, super.key});

  /// The current branch and its independent navigation stack.
  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    // Tapping the already-selected destination pops that branch back to its
    // root, which is the behaviour users expect from a bottom navigation bar.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.pin_outlined),
        selectedIcon: const Icon(Icons.pin),
        label: l10n.navAccounts,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.navSettings,
      ),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    if (!isWide) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: <NavigationRailDestination>[
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: destination.icon,
                  selectedIcon: destination.selectedIcon,
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
