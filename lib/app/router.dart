import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:utaha_authenticator/app/shell.dart';
import 'package:utaha_authenticator/features/about/presentation/about_screen.dart';
import 'package:utaha_authenticator/features/accounts/presentation/accounts_screen.dart';
import 'package:utaha_authenticator/features/backup/presentation/backup_screen.dart';
import 'package:utaha_authenticator/features/settings/presentation/settings_screen.dart';

part 'router.g.dart';

/// Route paths, kept in one place so navigation calls cannot drift from the
/// router configuration.
abstract final class AppRoutes {
  /// The account list.
  static const String accounts = '/';

  /// Settings.
  static const String settings = '/settings';

  /// About and licences.
  static const String about = '/settings/about';

  /// Backup, restore and migration.
  static const String backup = '/settings/backup';
}

/// Key used to observe the root navigator, so the app lock can push a modal
/// route above whatever the user was looking at.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Builds the application router.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.accounts,
    routes: <RouteBase>[
      // A stateful shell keeps each tab's navigation stack independent, so
      // switching tabs and coming back preserves where the user was.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.accounts,
                name: 'accounts',
                builder: (context, state) => const AccountsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'about',
                    name: 'about',
                    builder: (context, state) => const AboutScreen(),
                  ),
                  GoRoute(
                    path: 'backup',
                    name: 'backup',
                    builder: (context, state) => const BackupScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
