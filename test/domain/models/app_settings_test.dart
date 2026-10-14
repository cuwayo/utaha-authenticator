import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';

void main() {
  group('CodeGrouping.format', () {
    test('leaves the code untouched when grouping is none', () {
      expect(CodeGrouping.none.format('123456'), '123456');
    });

    test('splits into groups of two', () {
      expect(CodeGrouping.pairs.format('123456'), '12 34 56');
    });

    test('splits into groups of three', () {
      expect(CodeGrouping.triples.format('123456'), '123 456');
    });

    test('splits into groups of four, keeping a short tail', () {
      expect(CodeGrouping.quads.format('123456'), '1234 56');
      expect(CodeGrouping.quads.format('12345678'), '1234 5678');
    });

    test('handles seven- and eight-digit codes', () {
      expect(CodeGrouping.triples.format('1234567'), '123 456 7');
      expect(CodeGrouping.triples.format('12345678'), '123 456 78');
    });

    test('does not split a code shorter than the group size', () {
      expect(CodeGrouping.triples.format('12'), '12');
      expect(CodeGrouping.quads.format('123'), '123');
    });

    test('every grouping preserves the digits exactly', () {
      // Grouping is presentation only; it must never lose or alter a digit.
      const code = '12345678';
      for (final grouping in CodeGrouping.values) {
        expect(grouping.format(code).replaceAll(' ', ''), code);
      }
    });
  });

  group('AppSettings', () {
    test('defaults match the documented out-of-the-box behaviour', () {
      const settings = AppSettings.defaults;
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.useDynamicColor, isTrue);
      expect(settings.useAmoled, isFalse);
      expect(settings.seedColorValue, 0xFF5B3FA6);
      expect(settings.tapToReveal, isFalse);
      expect(settings.codeGrouping, CodeGrouping.triples);
      expect(settings.clipboardClearSeconds, 30);
      expect(settings.lockTimeoutSeconds, 30);
      expect(settings.listDensity, ListDensity.comfortable);
      expect(settings.appLockEnabled, isFalse);
      expect(settings.blockScreenshots, isTrue);
      expect(settings.onboardingCompleted, isFalse);
    });

    test('round-trips through the storage encoding', () {
      const original = AppSettings(
        themeMode: AppThemeMode.dark,
        useDynamicColor: false,
        useAmoled: true,
        seedColorValue: 0xFF00695C,
        tapToReveal: true,
        codeGrouping: CodeGrouping.pairs,
        clipboardClearSeconds: 60,
        lockTimeoutSeconds: 120,
        listDensity: ListDensity.compact,
        appLockEnabled: true,
        blockScreenshots: false,
        onboardingCompleted: true,
      );

      expect(AppSettings.fromMap(original.toMap()).toMap(), original.toMap());
    });

    test('an empty map yields the defaults', () {
      final restored = AppSettings.fromMap(const <String, String>{});
      expect(restored.toMap(), AppSettings.defaults.toMap());
    });

    test('malformed values fall back to defaults rather than throwing', () {
      // A settings row written by a newer or corrupted build must never crash
      // an older one.
      final restored = AppSettings.fromMap(const <String, String>{
        'theme_mode': 'not-a-mode',
        'code_grouping': 'not-a-grouping',
        'list_density': 'not-a-density',
        'clipboard_clear_seconds': 'banana',
        'lock_timeout_seconds': '',
        'seed_color': 'not-a-number',
        'use_dynamic_color': 'yes-please',
      });

      expect(restored.themeMode, AppThemeMode.system);
      expect(restored.codeGrouping, CodeGrouping.triples);
      expect(restored.listDensity, ListDensity.comfortable);
      expect(restored.clipboardClearSeconds, 30);
      expect(restored.lockTimeoutSeconds, 30);
      expect(restored.seedColorValue, 0xFF5B3FA6);
      expect(restored.useDynamicColor, isTrue);
    });

    test('copyWith changes only the named field', () {
      const original = AppSettings.defaults;
      final changed = original.copyWith(tapToReveal: true);
      expect(changed.tapToReveal, isTrue);
      expect(
        changed.toMap()..remove('tap_to_reveal'),
        original.toMap()..remove('tap_to_reveal'),
      );
    });
  });

  group('enum id round-tripping', () {
    test('AppThemeMode survives an unknown id', () {
      expect(AppThemeMode.fromId(null), AppThemeMode.system);
      expect(AppThemeMode.fromId('nope'), AppThemeMode.system);
      expect(AppThemeMode.fromId('dark'), AppThemeMode.dark);
    });

    test('CodeGrouping survives an unknown id', () {
      expect(CodeGrouping.fromId(null), CodeGrouping.triples);
      expect(CodeGrouping.fromId('nope'), CodeGrouping.triples);
      expect(CodeGrouping.fromId('quads'), CodeGrouping.quads);
    });

    test('ListDensity survives an unknown id', () {
      expect(ListDensity.fromId(null), ListDensity.comfortable);
      expect(ListDensity.fromId('nope'), ListDensity.comfortable);
      expect(ListDensity.fromId('compact'), ListDensity.compact);
    });
  });
}
