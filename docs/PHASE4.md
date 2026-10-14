# Phase 4 — Core UI

Status: **complete**. `flutter analyze` clean, **175 tests passing**, release APK builds
with no network permission.

Scope for this phase: the account list, countdown, copy, and account management
(reorder, pin, search, delete-with-undo). The add-account flows (QR scan and manual
entry) are Phase 4b.

## What was built

| File | Purpose |
|---|---|
| `lib/data/db/app_database.dart` | Accounts table (schema v2) + step-wise migration |
| `lib/data/repositories/drift_account_repository.dart` | Metadata persistence |
| `lib/data/repositories/in_memory_account_repository.dart` | Fake for tests |
| `lib/data/secure/in_memory_secret_repository.dart` | Fake keystore for tests |
| `lib/domain/repositories/account_repository.dart` | Metadata interface |
| `lib/domain/services/account_service.dart` | Coordinates metadata + secrets |
| `lib/domain/services/code_generator.dart` | Reads, uses and zeroes secrets |
| `lib/core/services/clipboard_service.dart` | Copy with guarded auto-clear |
| `lib/features/accounts/presentation/accounts_screen.dart` | The list, search, menu |
| `.../widgets/account_tile.dart` | One account row |
| `.../widgets/countdown_indicator.dart` | The countdown ring |
| `.../widgets/issuer_avatar.dart` | Deterministic letter avatar |
| `test/domain/services/account_service_test.dart` | 40 tests |
| `test/core/services/clipboard_service_test.dart` | 14 tests |

## The central design problem: two stores, one account

An account is split across two places — metadata in SQLite, secret in the platform
keystore — so every operation has to survive one write succeeding and the other
failing. The rules, each covered by a test:

- **Add** writes the secret **first**, then the metadata. The list is driven by
  metadata, so no row can ever appear with no key behind it. If the metadata write
  fails, the secret is deleted again so nothing is orphaned.
- **Delete** removes the metadata **first**. The account disappears from the UI even
  if the keystore delete fails, and `pruneOrphanedSecrets()` cleans up afterwards.
- **Orphans** (from a failed compensating delete, or a keystore reset) are pruned on
  demand; accounts whose secret has gone missing are *reported*, not deleted, because
  a keystore reset is often recoverable from a backup.

## Security-relevant decisions

**`Account` still holds no secret.** `CodeGenerator` reads the key, derives the code,
and zeroes the buffer in a `finally` block. No secret reaches widget state.

**Undo does not stash the secret in memory.** Deleting hides the row immediately but
defers the actual deletion for 5 seconds. The obvious implementation — delete at once
and keep the secret in the Dart heap in case the user taps undo — would put a live
secret in memory purely to support a UI affordance. Making the user wait a few seconds
is the better trade.

**The clipboard clear is guarded.** Before clearing, the service checks the clipboard
still holds *our* text. If the user copied a password in the meantime, it is left
alone — wiping an unrelated credential would be worse than leaving a stale OTP.

## Bugs found and fixed

- **`ReorderableListView.onReorder` is deprecated in Flutter 3.47.** The replacement,
  `onReorderItem`, *already* adjusts `newIndex` for the removed item, so the usual
  `newIndex > oldIndex ? newIndex - 1 : newIndex` idiom would have double-applied the
  adjustment and dropped accounts in the wrong place. Switched to `onReorderItem` and
  removed the manual adjustment.
- **A clipboard race.** `_lastCopied` was assigned *after* awaiting the platform copy,
  so an immediate `clearNowIfUnchanged()` saw no record and did nothing. State is now
  recorded before the await. Caught by a test.
- `code_generator.dart` was missing its `OtpType` import, and `accounts_screen.dart`
  its `ListDensity` import.

## Process note — my own mistake, worth recording

I lost significant time to a self-inflicted problem: my sync script pushed only `lib`,
so **every test edit I made was a no-op on the build host** while I read the same
unchanged failures back and kept "fixing" them. The script now mirrors the full source
tree (`lib test android ios pubspec.yaml analysis_options.yaml l10n.yaml`), excludes
generated files so `build_runner`/`gen-l10n` own them, and regenerates l10n on every
sync. `dart fix --apply` is run on the host and the result pulled back, so the two
copies cannot drift.

## Carried forward

- `accountCodesProvider` ticks once a second on a timer; the UI updates codes and the
  countdown from it. It is not paused when the app is backgrounded — Phase 6 will stop
  the tick on pause, which also matters for battery.
- `pruneOrphanedSecrets` and `findAccountsMissingSecrets` exist and are tested but are
  not yet called on startup; that belongs with the lock screen in Phase 6.
- Add-account entry points exist in the FAB sheet but are inert placeholders — Phase 4b.
- Edit is not yet exposed in the account menu (Phase 4b, alongside manual entry).
