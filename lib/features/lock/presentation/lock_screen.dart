import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/features/lock/presentation/lock_controller.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// The screen shown while the app is locked.
///
/// Deliberately shows nothing about the accounts behind it: no count, no
/// issuers, no codes. The lock exists to keep that off a screen someone else can
/// see, so the locked state must not leak it.
class LockScreen extends ConsumerStatefulWidget {
  /// Creates the lock screen.
  const new({required this.reason, super.key});

  /// Why the lock engaged, which changes the wording.
  final LockReason reason;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Prompt as soon as the screen appears, so the common case needs no tap.
    // Scheduled rather than called directly: showing a platform prompt during
    // the first build is unreliable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prompt());
    });
  }

  Future<void> _prompt() async {
    final l10n = AppLocalizations.of(context);
    await ref
        .read(lockControllerProvider.notifier)
        .unlock(reason: l10n.lockPromptReason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lock = ref.watch(lockControllerProvider);
    final busy = lock is Locked && lock.authenticating;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 44,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  kAppDisplayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (widget.reason) {
                    LockReason.launch => l10n.lockTitleLaunch,
                    LockReason.timeout => l10n.lockTitleTimeout,
                    LockReason.manual => l10n.lockTitleManual,
                  },
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                if (busy)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: () => unawaited(_prompt()),
                    icon: const Icon(Icons.lock_open),
                    label: Text(l10n.lockUnlockAction),
                  ),
                const SizedBox(height: 12),
                Text(
                  l10n.lockHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
