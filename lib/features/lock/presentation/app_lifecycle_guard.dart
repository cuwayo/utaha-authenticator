import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/features/lock/presentation/lock_controller.dart';
import 'package:utaha_authenticator/features/lock/presentation/lock_screen.dart';

/// Watches the app's lifecycle and drives the lock and the clipboard.
///
/// Wraps the whole app so backgrounding and resuming are handled once, in one
/// place, rather than by every screen.
class AppLifecycleGuard extends ConsumerStatefulWidget {
  /// Creates the guard around [child].
  const new({required this.child, super.key});

  /// The application content.
  final Widget child;

  @override
  ConsumerState<AppLifecycleGuard> createState() => _AppLifecycleGuardState();
}

class _AppLifecycleGuardState extends ConsumerState<AppLifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockControllerProvider.notifier);
    final clipboard = ref.read(clipboardServiceProvider);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.didEnterBackground();
        // A copied code should not sit on the clipboard while the app is not
        // even on screen. Only clears if the clipboard still holds our text.
        unawaited(clipboard.clearNowIfChanged());

      case AppLifecycleState.resumed:
        lock.didReturnToForeground();

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // `inactive` fires for transient interruptions such as the app switcher
        // or a notification shade, which must not count as leaving the app.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply the screenshot preference whenever it changes.
    final blockScreenshots = ref.watch(
      settingsControllerProvider.select(
        (value) => value.value?.blockScreenshots,
      ),
    );
    ref.listen(
      settingsControllerProvider.select(
        (value) => value.value?.blockScreenshots,
      ),
      (previous, next) => unawaited(_applyScreenSecurity(next)),
    );
    if (blockScreenshots != null) {
      // Applied once on first build as well as on change.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_applyScreenSecurity(blockScreenshots));
      });
    }

    return Stack(
      children: <Widget>[
        widget.child,
        // The lock is an overlay rather than a route swap, so the account list
        // keeps its state (scroll position, search text) across a lock.
        const _LockOverlay(),
      ],
    );
  }

  Future<void> _applyScreenSecurity(bool? block) async {
    final security = ref.read(screenSecurityProvider);
    if (block ?? AppSettings.defaults.blockScreenshots) {
      await security.enable();
    } else {
      await security.disable();
    }
  }
}

/// Covers the app while it is locked.
class _LockOverlay extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(lockControllerProvider);
    return switch (lock) {
      Locked(:final reason) => LockScreen(reason: reason),
      Unlocked() || LockDisabled() => const SizedBox.shrink(),
    };
  }
}
