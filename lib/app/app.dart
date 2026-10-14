import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/app/router.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/core/theme/app_theme.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/features/lock/presentation/app_lifecycle_guard.dart';
import 'package:utaha_authenticator/features/onboarding/presentation/onboarding_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// The application root.
///
/// Wraps the router in a [DynamicColorBuilder] so the theme can pick up the
/// device wallpaper on Android 12+, and rebuilds whenever settings change.
class UtahaApp extends ConsumerWidget {
  /// Creates the app root.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final router = ref.watch(routerProvider);

    // The settings stream emits its first value in the same frame the database
    // is opened. Falling back to defaults for that instant avoids flashing an
    // unstyled frame, and because defaults match a fresh install there is no
    // visible change either way.
    final settings = settingsAsync.value ?? AppSettings.defaults;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // When the user turns dynamic colour off we pass null, which makes
        // AppTheme fall back to the seeded violet palette.
        final lightScheme = settings.useDynamicColor ? lightDynamic : null;
        final darkScheme = settings.useDynamicColor ? darkDynamic : null;

        return MaterialApp.router(
          title: kAppDisplayName,
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: AppTheme.build(
            brightness: Brightness.light,
            dynamicScheme: lightScheme,
            useAmoled: settings.useAmoled,
            density: settings.listDensity,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            dynamicScheme: darkScheme,
            useAmoled: settings.useAmoled,
            density: settings.listDensity,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The guard sits above the router so backgrounding and resuming are
          // handled once for the whole app, and so the lock can cover every
          // route without the router knowing about it.
          builder: (context, child) => AppLifecycleGuard(
            // Onboarding sits inside the guard so the lock still covers it.
            child: OnboardingGate(child: child ?? const SizedBox.shrink()),
          ),
          routerConfig: router,
        );
      },
    );
  }
}
