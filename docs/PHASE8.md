# Phase 8 — Release preparation

Status: **complete**. All three CI gates pass locally:
`dart format --set-exit-if-changed` clean, `flutter analyze` clean, **385 tests passing**,
release APK builds.

## What was built

| File | Purpose |
|---|---|
| `README.md` | Project front door: features, building, architecture, honest status |
| `SECURITY.md` | Threat model: what is protected, what is not, how secrets are handled |
| `LICENSE` | MIT, with the bundled-artwork carve-out |
| `.github/workflows/ci.yml` | Format, analyze, test, release build, permission check |
| `android/key.properties.example` | Release signing template |
| `android/app/build.gradle.kts` | Real signing config with a hard failure when absent |
| `docs/STORE_LISTING.md` | Play and App Store copy, data-safety answers, checklist |
| `.gitignore` | Keystore and obfuscation symbols excluded |

## Two things I got wrong and fixed

### 1. A CI check that would have passed without checking anything

I wrote the "no network permission" step as a `grep` over `aapt2` output. When I ran
it, it printed **PASS** — and then I noticed `aapt2` had actually errored because the
APK path was wrong. `grep` found nothing in the error output and reported success.

That is a green tick on a check that verified nothing, which is worse than no check at
all: it would have hidden the exact regression it exists to catch.

Fixed by making it fail if the APK is missing, and by adding a second assertion that
`CAMERA` **is** present — so if the dump itself goes wrong, the step fails rather than
passing vacuously.

### 2. A documented warning that never appeared

I wrote that the release build "warns" when signed with the debug key. It does call
`logger.warn`, but **Gradle's configuration-phase output is filtered out of Flutter's
build log**, so nobody ever sees it. I verified this by building and grepping the
output: nothing.

Rather than document a warning that does not appear, the build now **fails outright**
when `key.properties` is missing:

```
Release signing is not configured.

  android/key.properties is missing, so this build would be
  signed with the debug key and could not be published.
```

CI opts in explicitly with `-PallowDebugSigning=true`, since it has no keystore and
only needs to prove the release build compiles.

A debug-signed release build is a genuine hazard: it installs fine, looks fine, and
cannot be published. The failure only shows up at the store.

## CI

Two jobs:

1. **analyze-and-test** — format check, `flutter analyze`, `flutter test`.
2. **build-android** — release APK, then verify it has no `INTERNET` permission, then
   upload the artifact.

A release build runs on every change because the failures that matter here are
release-only. R8 stripping `configureFlutterEngine` (Phase 6) could not be caught by
analyze, by unit tests, or by a debug build.

The Flutter version is pinned in one place so CI and local builds agree.

## Signing

`android/key.properties` is gitignored, as is the keystore. `key.properties.example`
documents the `keytool` invocation and warns that losing the key means losing the
ability to update the listing.

Verified by `apksigner` that a build without the config is signed with `CN=Android
Debug` — which is exactly what the new guard prevents by default.

## Store listing

`docs/STORE_LISTING.md` has both stores' copy within their character limits, the
Play **Data safety** answers, review notes explaining the deliberate absence of
network access, and a pre-release checklist.

The data-safety answer is "no data collected", and that claim is verifiable by
inspecting the APK rather than merely asserted — which is the point.

## Honest gaps

- **The app has still never run on a device.** The README says so plainly, in a table
  splitting what is verified from what is not, with the advice to keep an independent
  backup of 2FA secrets until you have tested it yourself.
- **No screenshots exist**, because there is no device to take them on. The store
  listing marks where they go.
- **Dart obfuscation is documented but not enabled by default**, because it requires
  archiving the symbol files; the README gives the exact command.
- **`docs/PHASE*.md` are working notes, not user documentation.** They are honest about
  bugs found and gaps remaining, which is useful for a maintainer and not for a user.

## Where the project stands

Eight phases, 58 lib files, 19 test files, 385 tests.

Every phase's claims were verified against a built artifact rather than assumed:
the RFC vectors reproduce, the release APK has no network permission, the backup
round-trips and rejects wrong passwords and corruption, and the screen-security code
survives R8.

What remains is not code. It is the things that need a device and a decision:

1. Replace or license the artwork (legal blocker).
2. Run it on a phone: camera, biometrics, screenshots, share sheet, file picker.
3. Time Argon2id on real hardware and tune the parameters.
4. Generate a release keystore.
