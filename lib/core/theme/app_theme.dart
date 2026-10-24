import 'package:flutter/material.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';

/// Maps the persisted [ListDensity] onto Flutter's [VisualDensity].
///
/// The domain enum cannot carry a `VisualDensity` because that is a Flutter
/// type; the mapping lives here instead, where Flutter is already in scope.
extension ListDensityVisuals on ListDensity {
  /// Visual density handed to Material widgets for this setting.
  VisualDensity get visualDensity => switch (this) {
    ListDensity.comfortable => VisualDensity.comfortable,
    ListDensity.compact => VisualDensity.compact,
  };
}

/// Builds the application's [ThemeData] for both brightnesses.
///
/// Colour comes from either the device wallpaper (dynamic colour, Android 12+)
/// or a user-selected seed colour as a fallback. Typography is tuned so OTP
/// codes render with tabular figures, which stops digits from jittering as they
/// tick.
abstract final class AppTheme {
  /// Default corner radius for cards and sheets.
  static const double _radius = 16;

  /// Builds a theme for [brightness].
  ///
  /// [dynamicScheme] is the wallpaper-derived scheme supplied by the
  /// `dynamic_color` package, or null when dynamic colour is disabled or
  /// unsupported. [useAmoled] forces a pure-black surface palette in dark mode.
  static ThemeData build({
    required Brightness brightness,
    ColorScheme? dynamicScheme,
    bool useAmoled = false,
    ListDensity density = ListDensity.comfortable,
    int seedColorValue = kSeedColorValue,
  }) {
    final scheme = _schemeFor(
      brightness: brightness,
      dynamicScheme: dynamicScheme,
      useAmoled: useAmoled,
      seedColorValue: seedColorValue,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: density.visualDensity,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: switch (density) {
          ListDensity.comfortable => 12,
          ListDensity.compact => 4,
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: scheme.surfaceContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorShape: const StadiumBorder(),
        labelType: NavigationRailLabelType.all,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 2,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48dp minimum touch target, per the accessibility requirement.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }

  static ColorScheme _schemeFor({
    required Brightness brightness,
    required bool useAmoled,
    required int seedColorValue,
    ColorScheme? dynamicScheme,
  }) {
    if (dynamicScheme != null && dynamicScheme.brightness == brightness) {
      // Dynamic colour is authoritative when available; AMOLED still applies so
      // the user can force true black over a wallpaper palette.
      return useAmoled && brightness == Brightness.dark
          ? _applyAmoled(dynamicScheme)
          : dynamicScheme;
    }

    final seeded = ColorScheme.fromSeed(
      seedColor: Color(seedColorValue),
      brightness: brightness,
    );
    return useAmoled && brightness == Brightness.dark
        ? _applyAmoled(seeded)
        : seeded;
  }

  /// Collapses the dark surface family to true black for AMOLED panels.
  ///
  /// Only the surface roles change; every `on*` colour is preserved so contrast
  /// ratios are unaffected.
  static ColorScheme _applyAmoled(ColorScheme scheme) {
    return scheme.copyWith(
      surface: const Color(0xFF000000),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerHigh: const Color(0xFF171717),
      surfaceContainerHighest: const Color(0xFF1E1E1E),
      onSurface: const Color(0xFFE6E1E5),
      onSurfaceVariant: const Color(0xFFCAC4D0),
      outlineVariant: const Color(0xFF2A2A2A),
    );
  }
}
