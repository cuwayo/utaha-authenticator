import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';
import 'package:utaha_authenticator/features/lock/presentation/lock_controller.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Preset seed colours offered when dynamic colour is unavailable or disabled.
///
/// These are chosen to produce accessible tonal palettes in both light and dark
/// schemes; the default violet leads the list.
const List<({String name, int value})> kSeedColors =
    <({String name, int value})>[
      (name: 'Violet', value: 0xFF5B3FA6),
      (name: 'Indigo', value: 0xFF3F51B5),
      (name: 'Teal', value: 0xFF00695C),
      (name: 'Green', value: 0xFF2E7D32),
      (name: 'Amber', value: 0xFFB26A00),
      (name: 'Rose', value: 0xFFB3261E),
    ];

/// Settings, grouped into sections that mirror how people think about them.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          _SectionHeader(title: l10n.settingsAppearance),
          _ThemeModeSelector(
            value: settings.themeMode,
            onChanged: (mode) => controller.mutate(
              (current) => current.copyWith(themeMode: mode),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.settingsDynamicColor),
            subtitle: Text(l10n.settingsDynamicColorBody),
            value: settings.useDynamicColor,
            onChanged: (value) => controller.mutate(
              (current) => current.copyWith(useDynamicColor: value),
            ),
          ),
          SwitchListTile(
            title: Text(l10n.settingsAmoled),
            subtitle: Text(l10n.settingsAmoledBody),
            value: settings.useAmoled,
            onChanged: (value) => controller.mutate(
              (current) => current.copyWith(useAmoled: value),
            ),
          ),
          _SeedColorPicker(
            // Dynamic colour overrides the seed, so the picker is dimmed while
            // it is on rather than silently having no effect.
            enabled: !settings.useDynamicColor,
            selected: settings.seedColorValue,
            onChanged: (value) => controller.mutate(
              (current) => current.copyWith(seedColorValue: value),
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: l10n.settingsCodes),
          SwitchListTile(
            title: Text(l10n.settingsTapToReveal),
            subtitle: Text(l10n.settingsTapToRevealBody),
            value: settings.tapToReveal,
            onChanged: (value) => controller.mutate(
              (current) => current.copyWith(tapToReveal: value),
            ),
          ),
          _CodeGroupingSelector(
            value: settings.codeGrouping,
            onChanged: (grouping) => controller.mutate(
              (current) => current.copyWith(codeGrouping: grouping),
            ),
          ),
          _ClipboardClearSelector(
            value: settings.clipboardClearSeconds,
            onChanged: (seconds) => controller.mutate(
              (current) => current.copyWith(clipboardClearSeconds: seconds),
            ),
          ),
          _DensitySelector(
            value: settings.listDensity,
            onChanged: (density) => controller.mutate(
              (current) => current.copyWith(listDensity: density),
            ),
          ),
          const Divider(height: 32),
          const Divider(height: 32),
          _SectionHeader(title: l10n.settingsSecurity),
          _AppLockSection(settings: settings, controller: controller),
          SwitchListTile(
            title: Text(l10n.settingsBlockScreenshots),
            subtitle: Text(l10n.settingsBlockScreenshotsBody),
            value: settings.blockScreenshots,
            onChanged: (value) => controller.mutate(
              (current) => current.copyWith(blockScreenshots: value),
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: l10n.settingsData),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.backupTitle),
            subtitle: Text(l10n.backupIntro),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('backup'),
          ),
          _SectionHeader(title: l10n.settingsAbout),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed('about'),
          ),
        ],
      ),
    );
  }
}

/// The app-lock toggle and its timeout.
///
/// Turning the lock on is refused when the device has no biometrics and no
/// screen lock: enabling it there would lock the user out of their own codes
/// with no way back in.
class _AppLockSection extends ConsumerStatefulWidget {
  const new({required this.settings, required this.controller});

  final AppSettings settings;
  final SettingsController controller;

  @override
  ConsumerState<_AppLockSection> createState() => _AppLockSectionState();
}

class _AppLockSectionState extends ConsumerState<_AppLockSection> {
  /// The choices offered, in seconds. Zero means "immediately".
  static const List<int> _timeouts = <int>[0, 30, 60, 300];

  Future<void> _toggle(bool enabled) async {
    final l10n = AppLocalizations.of(context);

    if (!enabled) {
      await widget.controller.mutate(
        (current) => current.copyWith(appLockEnabled: false),
      );
      return;
    }

    // Check the device can actually authenticate before turning the lock on.
    final auth = ref.read(biometricAuthProvider);
    final available = await auth.isAvailable();
    if (!mounted) return;

    if (!available) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.lockUnavailableTitle),
          content: Text(l10n.lockUnavailableBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionClose),
            ),
          ],
        ),
      );
      return;
    }

    // Confirm with a real prompt, so the user knows it works before relying on
    // it — being locked out by a lock that never worked is the worst outcome.
    final ok = await auth.authenticate(reason: l10n.lockEnableReason);
    if (!mounted) return;
    if (!ok) return;

    await widget.controller.mutate(
      (current) => current.copyWith(appLockEnabled: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = widget.settings.appLockEnabled;

    return Column(
      children: <Widget>[
        SwitchListTile(
          title: Text(l10n.settingsAppLock),
          subtitle: Text(l10n.settingsAppLockBody),
          value: enabled,
          onChanged: (value) => unawaited(_toggle(value)),
        ),
        if (enabled) ...<Widget>[
          _LabelledControl(
            label: l10n.settingsLockTimeout,
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                for (final seconds in _timeouts)
                  ChoiceChip(
                    label: Text(
                      seconds == 0
                          ? l10n.settingsLockImmediately
                          : l10n.settingsSecondsShort(seconds),
                    ),
                    selected: seconds == widget.settings.lockTimeoutSeconds,
                    onSelected: (_) => widget.controller.mutate(
                      (current) =>
                          current.copyWith(lockTimeoutSeconds: seconds),
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.settingsLockNow),
            onTap: () => ref.read(lockControllerProvider.notifier).lockNow(),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const new({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<AppThemeMode>(
        segments: <ButtonSegment<AppThemeMode>>[
          ButtonSegment<AppThemeMode>(
            value: AppThemeMode.system,
            label: Text(l10n.themeSystem),
            icon: const Icon(Icons.brightness_auto_outlined),
          ),
          ButtonSegment<AppThemeMode>(
            value: AppThemeMode.light,
            label: Text(l10n.themeLight),
            icon: const Icon(Icons.light_mode_outlined),
          ),
          ButtonSegment<AppThemeMode>(
            value: AppThemeMode.dark,
            label: Text(l10n.themeDark),
            icon: const Icon(Icons.dark_mode_outlined),
          ),
        ],
        selected: <AppThemeMode>{value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _SeedColorPicker extends StatelessWidget {
  const new({
    required this.enabled,
    required this.selected,
    required this.onChanged,
  });

  final bool enabled;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.settingsSeedColor,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.disabledColor,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final color in kSeedColors)
                _SeedSwatch(
                  name: color.name,
                  value: color.value,
                  selected: color.value == selected,
                  enabled: enabled,
                  onTap: () => onChanged(color.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(value);

    return Semantics(
      label: name,
      selected: selected,
      button: true,
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              // 48dp touch target, per the accessibility requirement.
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 22)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeGroupingSelector extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final CodeGrouping value;
  final ValueChanged<CodeGrouping> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _LabelledControl(
      label: l10n.settingsCodeGrouping,
      child: SegmentedButton<CodeGrouping>(
        segments: <ButtonSegment<CodeGrouping>>[
          ButtonSegment<CodeGrouping>(
            value: CodeGrouping.none,
            label: Text(CodeGrouping.none.format('123456')),
          ),
          ButtonSegment<CodeGrouping>(
            value: CodeGrouping.pairs,
            label: Text(CodeGrouping.pairs.format('123456')),
          ),
          ButtonSegment<CodeGrouping>(
            value: CodeGrouping.triples,
            label: Text(CodeGrouping.triples.format('123456')),
          ),
          ButtonSegment<CodeGrouping>(
            value: CodeGrouping.quads,
            label: Text(CodeGrouping.quads.format('123456')),
          ),
        ],
        selected: <CodeGrouping>{value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _ClipboardClearSelector extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  /// The choices offered, in seconds. Zero means "do not clear".
  static const List<int> _options = <int>[0, 15, 30, 60, 120];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _LabelledControl(
      label: l10n.settingsClipboardClear,
      child: Wrap(
        spacing: 8,
        children: <Widget>[
          for (final seconds in _options)
            ChoiceChip(
              label: Text(
                seconds == 0
                    ? l10n.settingsClipboardNever
                    : l10n.settingsSecondsShort(seconds),
              ),
              selected: seconds == value,
              onSelected: (_) => onChanged(seconds),
            ),
        ],
      ),
    );
  }
}

class _DensitySelector extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final ListDensity value;
  final ValueChanged<ListDensity> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _LabelledControl(
      label: l10n.settingsDensity,
      child: SegmentedButton<ListDensity>(
        segments: <ButtonSegment<ListDensity>>[
          ButtonSegment<ListDensity>(
            value: ListDensity.comfortable,
            label: Text(l10n.settingsDensityComfortable),
          ),
          ButtonSegment<ListDensity>(
            value: ListDensity.compact,
            label: Text(l10n.settingsDensityCompact),
          ),
        ],
        selected: <ListDensity>{value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _LabelledControl extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
        ],
      ),
    );
  }
}
