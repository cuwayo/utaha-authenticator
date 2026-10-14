# Phase 6 — Security and settings

Status: **complete**. `flutter analyze` clean, **357 tests passing**, release APK builds
with R8 shrinking enabled and no network permission.

## What was built

| File | Purpose |
|---|---|
| `lib/core/platform/biometric_auth.dart` | Biometric/device-credential interface + platform impl |
| `lib/core/platform/screen_security.dart` | Screenshot-blocking interface + platform impl |
| `lib/features/lock/presentation/lock_controller.dart` | The lock state machine |
| `lib/features/lock/presentation/lock_screen.dart` | The lock UI |
| `lib/features/lock/presentation/app_lifecycle_guard.dart` | Lifecycle wiring, lock overlay |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `FlutterFragmentActivity` + FLAG_SECURE channel |
| `android/app/proguard-rules.pro` | R8 keep rules |
| `android/app/build.gradle.kts` | Minify + shrink resources for release |
| `test/app/providers_test.dart` | Provider wiring tests (12) |
| `test/features/lock/lock_controller_test.dart` | Lock state machine tests (23) |

## Three serious bugs, all found by testing

### 1. No codes were ever generated in the real app

`accountCodesProvider` began with `await ref.watch(accountsProvider.future)`. **That
future never resolves for any provider type in this Riverpod version**, so the stream
never emitted — the account list would have shown every account with a blank code,
forever.

A diagnostic run confirmed it: the repository stream emits fine, but `.future` times
out on a plain `StreamProvider`, a `StreamNotifierProvider`, and the derived provider
alike. The fix watches the value instead of awaiting the future, which also makes the
stream restart when accounts change.

**Why the earlier tests missed it:** the Phase 4 boot test overrode
`accountCodesProvider` with a canned value, so nothing ever exercised the real wiring.
That is exactly the blind spot `test/app/providers_test.dart` now closes — it asserts a
stored secret actually turns into a code through the real providers.

### 2. R8 silently removed the screenshot protection

Release builds run R8. It stripped `configureFlutterEngine` and `onCreate` from
`MainActivity`, because they are only reached from the Android framework and R8 cannot
see those call sites. `dexdump` showed the class with an **empty virtual-method list** —
so the screen-security channel was never registered, and screenshot blocking did
nothing in release builds while working perfectly in debug.

Fixed with explicit keep rules, and verified against the built artifact: the channel
string is now present in the R8-processed DEX and `onCreate` survives. The rules file
documents why each entry exists.

This is the failure mode worth remembering: it cannot be caught by compiling, by
`flutter analyze`, by unit tests, or by running a debug build.

### 3. `isUnlocked` was false when the lock was disabled

`isUnlocked` returned `this is Unlocked`, which is false for `LockDisabled` — so with
the app lock switched off, the guard would have covered the UI with a lock screen that
could never be dismissed. Fixed to `this is! Locked`.

## Design decisions worth noting

**The lock is an overlay, not a route.** The account list keeps its scroll position and
search text across a lock, and the router needs no knowledge of the lock at all.

**Only a change to `appLockEnabled` re-locks the app.** Watching the whole settings
object would rebuild the controller whenever *anything* changed — so toggling dark mode
or list density would lock the user out mid-session. There is a regression test for
exactly that.

**Enabling the lock requires a real prompt first.** If the device has no biometrics and
no screen lock, the setting refuses to turn on and explains why — being locked out of
your own codes with no way back in is the worst possible outcome, and a lock that was
never tested is the likeliest way to get there.

**`FLAG_SECURE` is applied in `onCreate`**, before Dart runs, so the app is never
briefly capturable at launch.

**`MainActivity` extends `FlutterFragmentActivity`.** `local_auth` needs a
`FragmentActivity`; the plain `FlutterActivity` compiles and then fails at runtime.

**Backgrounding clears the clipboard** (only if it still holds our text) and records
the timestamp; resuming locks only if the grace period elapsed.

## Honest gaps

- **The biometric prompt has never been shown.** No device or emulator is available on
  this host, so `local_auth` is exercised only through a fake. The interface and the
  state machine are tested; the platform call is not.
- **`FLAG_SECURE` has not been observed blocking a screenshot** — verified only that the
  code and the channel string reach the release DEX.
- **iOS screenshot blocking is not implemented.** The iOS equivalent needs a
  `UITextField`-based trick; the calls are no-ops there, so behaviour differs by
  platform. Noted rather than silently skipped.
- **Argon2id's wall-clock cost on a phone is still unmeasured.**
- `pruneOrphanedSecrets` is implemented and tested but still not called at startup.

## Release configuration

- `isMinifyEnabled = true`, `isShrinkResources = true` for release.
- `proguard-rules.pro` keeps the activity, plugin classes, ML Kit models and annotations.
- **The release build is still signed with the debug key.** That must be replaced with a
  real signing config before publishing, and the keystore must stay out of version
  control.
