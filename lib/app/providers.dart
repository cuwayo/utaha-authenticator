import 'dart:async';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:utaha_authenticator/core/platform/biometric_auth.dart';
import 'package:utaha_authenticator/core/platform/screen_security.dart';
import 'package:utaha_authenticator/core/services/clipboard_service.dart';
import 'package:utaha_authenticator/data/db/app_database.dart';
import 'package:utaha_authenticator/data/repositories/drift_account_repository.dart';
import 'package:utaha_authenticator/data/repositories/drift_settings_repository.dart';
import 'package:utaha_authenticator/data/secure/secure_secret_repository.dart';
import 'package:utaha_authenticator/domain/backup/backup_service.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';
import 'package:utaha_authenticator/domain/repositories/settings_repository.dart';
import 'package:utaha_authenticator/domain/services/account_importer.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';

part 'providers.g.dart';

/// Opens the application database.
///
/// Kept alive for the whole process: opening SQLite is comparatively expensive
/// and there is exactly one database per install.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
}

/// Provides the keystore-backed secret store.
@Riverpod(keepAlive: true)
SecretRepository secretRepository(Ref ref) => SecureSecretRepository();

/// Provides the settings store.
@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    DriftSettingsRepository(ref.watch(appDatabaseProvider));

/// Provides the account metadata store.
@Riverpod(keepAlive: true)
AccountRepository accountRepository(Ref ref) =>
    DriftAccountRepository(ref.watch(appDatabaseProvider));

/// Authenticates the user with biometrics or a device credential.
@Riverpod(keepAlive: true)
BiometricAuth biometricAuth(Ref ref) => PlatformBiometricAuth();

/// Blocks screenshots and the app-switcher thumbnail.
@Riverpod(keepAlive: true)
ScreenSecurity screenSecurity(Ref ref) => const PlatformScreenSecurity();

/// Provides the current time. Overridden in tests with a fixed clock.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();

/// Coordinates account metadata with the secret store.
@Riverpod(keepAlive: true)
AccountService accountService(Ref ref) => AccountService(
  accounts: ref.watch(accountRepositoryProvider),
  secrets: ref.watch(secretRepositoryProvider),
);

/// Turns scanned, picked or typed input into accounts.
@Riverpod(keepAlive: true)
AccountImporter accountImporter(Ref ref) =>
    AccountImporter(ref.watch(accountServiceProvider));

/// Exports and restores encrypted backups.
@Riverpod(keepAlive: true)
BackupService backupService(Ref ref) => BackupService(
  accounts: ref.watch(accountRepositoryProvider),
  secrets: ref.watch(secretRepositoryProvider),
);

/// Generates OTP codes, reading and zeroing secrets internally.
@Riverpod(keepAlive: true)
CodeGenerator codeGenerator(Ref ref) => CodeGenerator(
  secrets: ref.watch(secretRepositoryProvider),
  clock: ref.watch(clockProvider),
);

/// The system clipboard.
@Riverpod(keepAlive: true)
ClipboardPort clipboardPort(Ref ref) => const SystemClipboard();

/// Copies codes and clears them again after a delay.
@Riverpod(keepAlive: true)
ClipboardService clipboardService(Ref ref) {
  final service = ClipboardService(ref.watch(clipboardPortProvider));
  ref.onDispose(service.dispose);
  return service;
}

/// Exposes the current settings and writes changes back to storage.
///
/// The UI reads [SettingsController.build]'s stream; call [SettingsController.update]
/// to change a value. Reading and writing through one provider means there is no
/// window where the UI shows a value that storage does not agree with.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Stream<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).watch();
  }

  /// Persists [settings].
  ///
  /// Named `setSettings` rather than `update` because Riverpod's generated base
  /// class already declares an `update` with a different signature.
  ///
  /// The provider's own state updates from the repository's stream, so this does
  /// not assign state directly — that keeps the database as the single source of
  /// truth even if a write is made from somewhere else.
  Future<void> setSettings(AppSettings settings) {
    return ref.read(settingsRepositoryProvider).save(settings);
  }

  /// Applies [transform] to the current settings and saves the result.
  ///
  /// Does nothing when settings have not loaded yet, which avoids clobbering
  /// stored values with defaults during startup.
  Future<void> mutate(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = state.value;
    if (current == null) return;
    await setSettings(transform(current));
  }
}

/// All accounts, in display order.
///
/// Driven by the database's own change stream, so any write — including one made
/// by a later phase's import flow — refreshes the list without extra wiring.
@Riverpod(keepAlive: true)
Stream<List<Account>> accounts(Ref ref) {
  return ref.watch(accountServiceProvider).watchAll();
}

/// The current search text used to filter the account list.
@Riverpod(keepAlive: true)
class AccountSearchQuery extends _$AccountSearchQuery {
  @override
  String build() => '';

  /// The current query.
  String get query => state;

  /// Replaces the query. An empty string clears the filter.
  set query(String value) => state = value;

  /// Clears the filter.
  void clear() => state = '';
}

/// Accounts scheduled for deletion but still undoable.
///
/// Deleting an account is destructive and easy to trigger by accident, so the
/// row disappears immediately but the actual deletion is deferred until the undo
/// window closes.
///
/// The secret deliberately stays in the keystore for that whole window. The
/// alternative — deleting at once and stashing the secret in memory to restore it
/// on undo — would put a live secret in the Dart heap purely to support an undo,
/// which is a worse trade than making the user wait a few seconds.
@Riverpod(keepAlive: true)
class PendingDeletions extends _$PendingDeletions {
  final Map<String, Timer> _timers = <String, Timer>{};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const <String>{};
  }

  /// Hides [accountId] and commits its deletion after [window].
  void schedule(
    String accountId, {
    Duration window = const Duration(seconds: 5),
  }) {
    _timers[accountId]?.cancel();
    state = <String>{...state, accountId};
    _timers[accountId] = Timer(window, () async {
      _timers.remove(accountId);
      state = <String>{...state}..remove(accountId);
      await ref.read(accountServiceProvider).delete(accountId);
    });
  }

  /// Cancels a pending deletion, restoring the account to the list.
  void undo(String accountId) {
    _timers.remove(accountId)?.cancel();
    state = <String>{...state}..remove(accountId);
  }
}

/// The accounts matching the current search, in display order.
@Riverpod(keepAlive: true)
List<Account> visibleAccounts(Ref ref) {
  final all = ref.watch(accountsProvider).value ?? const <Account>[];
  final pending = ref.watch(pendingDeletionsProvider);

  final live = pending.isEmpty
      ? all
      : all.where((a) => !pending.contains(a.id)).toList(growable: false);

  final query = ref.watch(accountSearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return live;
  return live
      .where((a) => a.searchHaystack.contains(query))
      .toList(growable: false);
}

/// The code each account is currently showing, refreshed once a second.
///
/// Emits a map keyed by account id so the list can look up one account's code
/// without re-deriving every other code on each rebuild.
///
/// Ticks are aligned to whole wall-clock seconds, so the displayed countdown
/// changes in step with the system clock rather than drifting with frame timing.
///
/// The account list is read with `ref.watch(...).value` rather than
/// `await ...future`. Awaiting a provider's `future` does not resolve for these
/// provider types in this Riverpod version, which would leave this stream stuck
/// before its first emit and the list showing no codes at all. Watching the
/// value instead means the stream restarts when the accounts change, and an
/// empty list simply produces an empty map.
@Riverpod(keepAlive: true)
Stream<Map<String, AccountCode>> accountCodes(Ref ref) async* {
  final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
  final generator = ref.watch(codeGeneratorProvider);

  while (true) {
    final codes = <String, AccountCode>{};
    for (final account in accounts) {
      final code = await generator.generate(account);
      if (code != null) codes[account.id] = code;
    }
    yield codes;

    // Sleep until the next whole second so ticks stay aligned with the clock.
    final now = DateTime.now();
    final untilNextSecond = 1000 - now.millisecond;
    await Future<void>.delayed(Duration(milliseconds: untilNextSecond));
  }
}

/// A clipboard implementation backed by Flutter's [Clipboard].
class SystemClipboard implements ClipboardPort {
  /// Creates the system clipboard port.
  const new();

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> currentText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}
