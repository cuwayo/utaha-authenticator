import 'package:flutter/material.dart';

/// Typography helpers for the parts of the UI that display live numbers.
abstract final class AppTypography {
  /// Tabular (monospaced) digits.
  ///
  /// Applied to every OTP code so that changing digits do not shift the glyphs
  /// sideways — proportional figures make a ticking code visibly jitter.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// Style for the large code shown on an account row.
  ///
  /// Scales with the user's text-size setting because it is derived from the
  /// theme's own display style rather than a hard-coded size.
  static TextStyle otpCode(ThemeData theme, {bool compact = false}) {
    final base = theme.textTheme.displaySmall ?? const TextStyle();
    final size = (base.fontSize ?? 36) * (compact ? 0.78 : 1);
    return base.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      fontFeatures: tabularFigures,
      color: theme.colorScheme.onSurface,
    );
  }

  /// Style for the small countdown label beside a progress indicator.
  static TextStyle countdown(ThemeData theme) {
    final base = theme.textTheme.labelMedium ?? const TextStyle();
    return base.copyWith(
      fontFeatures: tabularFigures,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// Style for the manual-entry secret field, which is Base32 and benefits from
  /// tabular figures and generous letter spacing.
  static TextStyle secretInput(ThemeData theme) {
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    return base.copyWith(fontFeatures: tabularFigures, letterSpacing: 1.2);
  }
}
