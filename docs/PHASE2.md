# Phase 2 — Foundation

Status: **complete**. `flutter analyze` clean, 51 tests passing, release APK builds.

## What was built

| Area | Files |
|---|---|
| Project config | `pubspec.yaml`, `analysis_options.yaml`, `l10n.yaml` |
| Identity | `lib/core/constants/app_constants.dart` |
| Theming | `lib/core/theme/app_theme.dart`, `app_typography.dart` |
| Domain models | `lib/domain/models/app_settings.dart`, `display_preferences.dart` |
| Domain interfaces | `lib/domain/repositories/secret_repository.dart`, `settings_repository.dart` |
| Storage | `lib/data/secure/secure_secret_repository.dart`, `lib/data/db/app_database.dart`, `lib/data/repositories/*` |
| Utilities | `lib/core/utils/base32.dart`, `zeroing.dart`, `lib/core/errors/failures.dart` |
| App shell | `lib/app/app.dart`, `router.dart`, `shell.dart`, `providers.dart`, `lib/main.dart` |
| Screens | `lib/features/accounts/presentation/accounts_screen.dart`, `settings/.../settings_screen.dart`, `about/.../about_screen.dart` |
| Shared UI | `lib/core/widgets/empty_state.dart` |
| Localisation | `lib/l10n/app_en.arb` (60+ keys) |
| Android | `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`, `res/xml/backup_rules.xml`, full launcher icon set |
| Tests | `test/core/utils/base32_test.dart`, `test/core/theme/app_theme_test.dart`, `test/domain/models/app_settings_test.dart`, `test/features/accounts/accounts_screen_test.dart`, `test/app/app_boot_test.dart` |

## Verified on the build host

```
flutter analyze   →  No issues found!
flutter test      →  51 passed
flutter build apk --release  →  app-release.apk, BUILD_EXIT=0
```

Release APK identity and permissions, read from the built artifact:

```
package: moe.nanakura.utaha   versionName 1.0.0   targetSdk 36
application-label: Utaha Authenticator
uses-permission: CAMERA, USE_BIOMETRIC, USE_FINGERPRINT
INTERNET occurrences: 0
```

## Security outcomes

- **No network capability in release.** The Flutter embedding declares `INTERNET`
  and pulls in `ACCESS_NETWORK_STATE`; both are removed explicitly with
  `tools:node="remove"` in the manifest rather than merely not requested, so the
  build fails if anything reintroduces them. Verified against the built APK.
- `android:allowBackup="false"` plus explicit `data_extraction_rules.xml` and
  `backup_rules.xml` excluding every domain, so secrets cannot reach device backups.
- Secrets go only to the platform keystore (`flutter_secure_storage`), with
  `unlocked_this_device` on iOS so they are never restored onto another device.
- `Uint8List` is used for secret material with an explicit `zero()` helper; the
  limitation that Dart `String`s cannot be wiped is documented in `zeroing.dart`.
- Only non-secret metadata is stored in SQLite.

## Decisions worth remembering

- **`dynamic_color` pinned to `^1.9.0`.** Version 2.x migrated to the new
  `material_ui` package, whose `ColorScheme` is a *different class* from
  `package:flutter/material.dart`'s, so 2.x schemes cannot be passed to
  `ThemeData`. 1.9.0 is the last release targeting the stable Flutter Material API.
  Revisit when the ecosystem consolidates on `material_ui`.
- **`build_runner` pinned to `^2.17.0`.** 2.16.2 is incompatible with `build`
  4.1.0 (`BuildStepImpl` misses `librarySourceSink`) and fails to compile.
- **`custom_lint` dropped.** 0.8.1 pins `analyzer ^8`, which conflicts with
  `json_serializable` and `drift_dev` (both `analyzer >=13`). `riverpod_lint`
  3.1.9 uses `analyzer_plugin` and no longer needs it.
- **`very_good_analysis` with two rules relaxed**: `public_member_api_docs` off
  (noise in generated-heavy code) and `lines_longer_than_80_chars` off.
- **`dart fix --apply` rewrites constructors to `const new(...)`**, which is valid
  modern Dart and passes the analyzer.

## Icon provenance — READ THIS

The launcher icon is **user-supplied anime character artwork**, not an original
mark. It was requested explicitly, after the project brief's branding rule
("Do not use any existing anime, manga, or other copyrighted character artwork
or likeness") was flagged and the user chose to proceed anyway.

Consequences that must be resolved before any public release:

1. **Licensing.** This is third-party character art of unclear provenance. It
   cannot ship in an open-source repository or an app store listing without a
   licence from the rights holder. A store takedown is a realistic risk.
2. **The themed icon is effectively unusable.** Android 13+ monochrome icons
   need a single-colour silhouette; a derived threshold of the art produces a
   black blob. It is generated and wired up, but it will look wrong.
3. **Legibility.** A 1254×1254 illustration has no small-size form. The crop was
   tuned to the character's head so it survives at 48dp, but it reads as a
   portrait, not an icon.

To swap in an original mark later, replace the source image and re-run
`generate_icons.sh`; nothing else in the app depends on the artwork.

## Open items carried into later phases

- `assets/icon/icon.png` is used by the About screen and has a fallback if absent.
- The splash screen is still Flutter's default `LaunchTheme`; Phase 7.
- Onboarding (3 screens max) is not built yet; `onboardingCompleted` is already
  persisted so the flag exists to key off.
- `lockTimeoutSeconds` and `appLockEnabled` are stored but not enforced; Phase 6.
- The build host has no `/dev/kvm`, so there is no emulator: on-device
  integration tests need a physical device over adb.
