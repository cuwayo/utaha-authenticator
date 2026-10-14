import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart'
    show AppSettings;

part 'lock_controller.g.dart';

/// Why the lock screen is currently showing.
enum LockReason {
  /// The app is starting and the lock is enabled.
  launch,

  /// The app returned from the background after the grace period.
  timeout,

  /// The user asked to lock it now.
  manual,
}

/// The state of the app lock.
sealed class LockState {
  const new();

  /// Whether the account list may be shown.
  ///
  /// True for both [Unlocked] and [LockDisabled]: with the lock switched off
  /// there is nothing to unlock, so the UI must not be covered.
  bool get isUnlocked => this is! Locked;
}

/// The app is locked and waiting for authentication.
final class Locked extends LockState {
  /// Creates a locked state.
  const new({required this.reason, this.authenticating = false});

  /// Why the lock engaged.
  final LockReason reason;

  /// Whether a prompt is currently on screen.
  final bool authenticating;

  /// Returns a copy with [authenticating] replaced.
  Locked copyWith({bool? authenticating}) => Locked(
    reason: reason,
    authenticating: authenticating ?? this.authenticating,
  );
}

/// The app is unlocked.
final class Unlocked extends LockState {
  /// Creates an unlocked state.
  const new();
}

/// The app lock is switched off in settings, so nothing is locked.
final class LockDisabled extends LockState {
  /// Creates a disabled state.
  const new();
}

/// Owns whether the app is currently locked.
///
/// The lock has three routes into a locked state — a cold start, returning from
/// the background after the grace period, and an explicit "lock now" — and has
/// to avoid two mistakes that are each bad in their own way:
///
/// * **Locking too eagerly.** Prompting on every trivial resume, or while the
///   user is mid-copy, makes the app unusable.
/// * **Locking too late.** Leaving codes visible after the phone has been put
///   down defeats the point.
///
/// The balance is [AppSettings.lockTimeoutSeconds]: the app may be backgrounded
/// for less than that without re-prompting.
@Riverpod(keepAlive: true)
class LockController extends _$LockController {
  DateTime? _backgroundedAt;

  /// Guards against starting a second prompt while one is on screen, which some
  /// platforms handle badly.
  bool _prompting = false;

  @override
  LockState build() {
    // Watching the whole settings object would re-run `build` when *any*
    // setting changed, so toggling dark mode or list density would re-lock an
    // unlocked app. Only a change to `appLockEnabled` should do that, so the
    // previous value is compared explicitly.
    final settings = ref.watch(settingsControllerProvider).value;
    final enabled = settings?.appLockEnabled;

    final previous = _lastEnabled;
    _lastEnabled = enabled;

    // Until settings load, report disabled rather than locked: a slow database
    // read must not produce a lock-screen flash on a device where the lock is
    // switched off.
    if (enabled == null || !enabled) return const LockDisabled();

    // Turning the lock on takes effect immediately. When the flag was already
    // on, keep whatever state the controller is in so a rebuild caused by an
    // unrelated change cannot silently unlock the app.
    if (previous == true && stateOrNull is Unlocked) return const Unlocked();

    return const Locked(reason: LockReason.launch);
  }

  /// The `appLockEnabled` value seen on the previous `build`.
  bool? _lastEnabled;

  /// The current state, or null before the first build completes.
  @override
  LockState? get stateOrNull {
    try {
      return state;
    } on Object {
      return null;
    }
  }

  /// Records that the app went to the background.
  void didEnterBackground() {
    if (state is LockDisabled) return;
    _backgroundedAt = DateTime.now();
  }

  /// Records that the app came back, and locks if the grace period elapsed.
  ///
  /// Does nothing when the app is already locked, so returning to a locked
  /// screen cannot restart a prompt that is already up.
  void didReturnToForeground() {
    if (state is! Unlocked) return;

    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null || !settings.appLockEnabled) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;

    final away = DateTime.now().difference(backgroundedAt);
    // A timeout of zero means "lock as soon as the app is not in front", which
    // is the strictest setting.
    if (away >= Duration(seconds: settings.lockTimeoutSeconds)) {
      state = const Locked(reason: LockReason.timeout);
    }
  }

  /// Sets the recorded background instant, for tests.
  ///
  /// The timeout is measured against the wall clock, so a test cannot wait for
  /// it; this lets a test move the recorded instant into the past instead.
  @visibleForTesting
  DateTime? get debugBackgroundedAt => _backgroundedAt;

  @visibleForTesting
  set debugBackgroundedAt(DateTime? instant) => _backgroundedAt = instant;

  /// Locks immediately, regardless of the grace period.
  void lockNow() {
    if (state is LockDisabled) return;
    state = const Locked(reason: LockReason.manual);
  }

  /// Prompts for authentication and unlocks on success.
  ///
  /// [reason] is shown by the OS in its prompt, and is passed in rather than
  /// looked up here so this controller needs no `BuildContext` and stays
  /// testable.
  ///
  /// Returns true when the app ended up unlocked. Safe to call repeatedly: a
  /// second call while a prompt is on screen returns immediately.
  Future<bool> unlock({required String reason}) async {
    // Narrowed to `Locked` so `reason` is reachable; the guards above are what
    // make that safe.
    final current = state;
    if (current is! Locked) return true;
    if (_prompting) return false;

    _prompting = true;
    state = Locked(reason: current.reason, authenticating: true);

    try {
      final auth = ref.read(biometricAuthProvider);
      final ok = await auth.authenticate(reason: reason);
      if (ok) {
        _backgroundedAt = null;
        state = const Unlocked();
        return true;
      }
      // Failed or cancelled: stay locked, and let the user try again.
      state = Locked(reason: current.reason);
      return false;
    } on Object {
      // The platform interface promises not to throw, but a lock screen that
      // crashes would be worse than one that stays shut.
      state = Locked(reason: current.reason);
      return false;
    } finally {
      _prompting = false;
    }
  }
}
