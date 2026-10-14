import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/core/theme/app_theme.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';

void main() {
  group('AppTheme.build', () {
    test('uses Material 3', () {
      expect(AppTheme.build(brightness: Brightness.light).useMaterial3, isTrue);
    });

    test(
      'falls back to the brand seed colour when dynamic colour is absent',
      () {
        final theme = AppTheme.build(brightness: Brightness.light);
        final expected = ColorScheme.fromSeed(
          seedColor: const Color(kSeedColorValue),
        );
        // The seeded scheme must be the violet palette, not Flutter's default
        // purple, otherwise dynamic-colour-unavailable devices look unbranded.
        expect(theme.colorScheme.primary, expected.primary);
        expect(theme.colorScheme.brightness, Brightness.light);
      },
    );

    test('produces a dark scheme when asked', () {
      final theme = AppTheme.build(brightness: Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.brightness, Brightness.dark);
    });

    test('AMOLED collapses the dark surface family to true black', () {
      final theme = AppTheme.build(
        brightness: Brightness.dark,
        useAmoled: true,
      );
      expect(theme.colorScheme.surface, const Color(0xFF000000));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.colorScheme.surfaceContainerLowest, const Color(0xFF000000));
    });

    test('AMOLED does not alter the light scheme', () {
      // True black is meaningless in light mode; asking for it there must not
      // produce a black-on-black theme.
      final plain = AppTheme.build(brightness: Brightness.light);
      final amoled = AppTheme.build(
        brightness: Brightness.light,
        useAmoled: true,
      );
      expect(amoled.colorScheme.surface, plain.colorScheme.surface);
    });

    test('AMOLED preserves the onSurface contrast colour', () {
      final theme = AppTheme.build(
        brightness: Brightness.dark,
        useAmoled: true,
      );
      // The foreground must stay light so text remains readable on black.
      final luminance = theme.colorScheme.onSurface.computeLuminance();
      expect(luminance, greaterThan(0.5));
    });

    test('accepts a dynamic scheme for the matching brightness', () {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00695C),
      );
      final theme = AppTheme.build(
        brightness: Brightness.light,
        dynamicScheme: dynamicScheme,
      );
      expect(theme.colorScheme.primary, dynamicScheme.primary);
    });

    test('ignores a dynamic scheme for the wrong brightness', () {
      // A light scheme must never be applied to a dark theme.
      final lightScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00695C),
      );
      final theme = AppTheme.build(
        brightness: Brightness.dark,
        dynamicScheme: lightScheme,
      );
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, isNot(lightScheme.primary));
    });

    test('applies the requested list density', () {
      final comfortable = AppTheme.build(brightness: Brightness.light);
      final compact = AppTheme.build(
        brightness: Brightness.light,
        density: ListDensity.compact,
      );
      expect(comfortable.visualDensity, VisualDensity.comfortable);
      expect(compact.visualDensity, VisualDensity.compact);
    });

    test('interactive controls meet the 48dp minimum touch target', () {
      // Accessibility requirement: min 48dp touch targets.
      final theme = AppTheme.build(brightness: Brightness.light);
      final buttonSize = theme.filledButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      expect(buttonSize?.height, greaterThanOrEqualTo(48));
      expect(buttonSize?.width, greaterThanOrEqualTo(48));
    });
  });
}
