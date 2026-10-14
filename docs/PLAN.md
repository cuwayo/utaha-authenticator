# Utaha Authenticator — Phase 1 Plan

> Open-source, offline-first 2FA app. Flutter (Material 3) targeting Android first, iOS kept working.

## 1. Verified environment

Build host: `root@95.216.212.168` (Ubuntu 26.04 LTS, 8 cores, 15 GB RAM, 287 GB free).

| Component | Version | Location |
|---|---|---|
| Flutter | 3.47.7 stable | `/opt/flutter` |
| Dart | 3.13.5 | bundled |
| JDK | OpenJDK 17.0.20.1 LTS | `/usr/lib/jvm/java-17-openjdk-amd64` |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools 37.0.1 | `/opt/android-sdk` |

`flutter doctor`: Flutter ✓, Android toolchain ✓ (all licenses accepted), Network ✓.
Chrome ✗ and Linux-desktop ✗ are **not used** by this project.

**Baseline proven:** `flutter build apk --debug` → `app-debug.apk`, `BUILD_EXIT=0`,
`package: name='moe.nanakura.utaha'`.

**Constraint:** the host has no `/dev/kvm`, so **no Android emulator**. `flutter test`,
`flutter analyze`, and `flutter build apk` all run; on-device integration tests require a
physical device (or a machine with KVM).

## 2. Identifiers (locked)

| Thing | Value |
|---|---|
| Display name | Utaha Authenticator |
| Dart package | `utaha_authenticator` |
| applicationId / bundle ID | `moe.nanakura.utaha` |
| Android namespace + Kotlin package | `moe.nanakura.utaha` |
| Backup extension / MIME | `.utaha` / `application/vnd.nanakura.utaha-backup` |
| Domain | `nanakura.moe` |
| Seed color | `#5B3FA6` |

Applied: `android/app/build.gradle.kts` (namespace + applicationId),
`MainActivity.kt` moved to `kotlin/moe/nanakura/utaha/`, iOS `PRODUCT_BUNDLE_IDENTIFIER`.
Remaining in Phase 2: `android:label` in the manifest.

## 3. Architecture — feature-first clean architecture

```
lib/
  main.dart                    # entrypoint, runApp
  app/                         # app shell
    app.dart                   # root MaterialApp.router
    router.dart                # go_router + predictive back
    bootstrap.dart             # ProviderScope overrides, DI wiring
  core/                        # cross-cutting, no feature imports
    constants/                 # ids, mime types, durations
    theme/                     # ColorScheme.fromSeed, M3 type scale, density
    errors/                    # Failure types + friendly copy
    utils/                     # base32 codec, byte zeroing, formatting
    widgets/                   # shared widgets
  data/                        # implementations
    secure/                    # flutter_secure_storage wrapper (secrets)
    db/                        # drift database + DAOs (metadata only)
    repositories/              # domain repo implementations
  domain/                      # PURE DART — zero Flutter imports
    models/                    # Account, OtpType, OtpAlgorithm, BackupFile...
    otp/                       # RFC 4226 (HOTP) + RFC 6238 (TOTP)
    otpauth/                   # otpauth:// parse + serialize
    migration/                 # otpauth-migration protobuf parser
    backup/                    # .utaha codec: Argon2id + AES-256-GCM
    repositories/              # abstract interfaces
  features/                    # UI, one folder per feature
    accounts/  scan/  settings/  backup/  lock/  onboarding/  about/
  l10n/                        # app_en.arb (+ generated)
```

**Dependency rule:** `features → domain ← data`. `domain` depends on nothing but Dart and
pure-Dart `cryptography`. The OTP core is therefore fully unit-testable with no Flutter binding.

**State:** Riverpod 3 (`flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`).
**Routing:** `go_router` 18, typed routes, `PopScope` for predictive back.

## 4. Storage split (security-critical)

| Data | Store | Rationale |
|---|---|---|
| OTP secrets | `flutter_secure_storage` (Android Keystore / iOS Keychain) | never on disk in plaintext |
| Account metadata (issuer, label, tags, order, pin) | drift/SQLite | non-secret, needs query + reorder |
| Settings | drift (same DB) | single source of truth |
| Backup passphrase | **never persisted** | held in memory for one operation, zeroed after |

`SharedPreferences` is **not used for secrets** — and not for settings either, to keep one
source of truth.

## 5. Package set (all versions resolved live from pub.dev)

**Runtime**
`flutter_riverpod` 3.4.3 · `riverpod_annotation` 4.0.7 · `go_router` 18.0.2 ·
`mobile_scanner` 7.4.2 · `flutter_secure_storage` 11.2.0 · `local_auth` 3.0.2 ·
`dynamic_color` 2.1.0 · `cryptography` 2.9.0 · `protobuf` 6.1.0 · `drift` 2.35.2 ·
`drift_flutter` 0.3.1 · `file_picker` 13.1.0 · `share_plus` 13.3.1 · `image_picker` 1.2.4 ·
`path_provider` 2.1.6 · `url_launcher` 6.3.3 · `package_info_plus` 10.2.2 ·
`device_info_plus` 13.3.0 · `intl` 0.20.3 · `collection` · `crypto` · `convert`

**Dev**
`very_good_analysis` 11.0.0 · `riverpod_generator` 4.0.9 · `build_runner` 2.16.2 ·
`json_serializable` 6.14.1 · `custom_lint` 0.8.1 · `riverpod_lint` 3.1.9 · `mocktail` 1.0.5

**Deliberate exclusions**
- `otp` 3.2.1 — rejected; we implement RFC 4226/6238 ourselves and prove it against the RFC vectors.
- `sqlite3_flutter_libs` — **EOL** (`0.6.0+eol`); `drift_flutter` handles natives now.
- `isar` — unmaintained for the current Flutter stable; drift is the safer choice.
- `google_fonts` — rejected; it fetches fonts at runtime, which would require network.
  Typography uses the platform font with `FontFeature.tabularFigures()`.

## 6. Backup format `.utaha`

```
magic "UTAHA" (5B) | format version (u8) | kdf id (u8) | kdf params |
salt (16B) | nonce (12B) | ciphertext || tag (AES-256-GCM)
```
- KDF: **Argon2id** (default) with PBKDF2-HMAC-SHA256 as a documented fallback.
  Pure-Dart Argon2id is CPU-heavy → run in an isolate via `compute` with a progress indicator.
- AEAD: AES-256-GCM, AAD = the header bytes so the header is tamper-evident.
- Version header allows the format to evolve; unknown versions fail with a clear message.

## 7. Security checklist (enforced, not aspirational)

- No `INTERNET` permission in the **main** manifest — the release APK ships with zero
  network permission. (Verified: it currently appears only in Flutter's debug/profile manifests,
  which are not part of a release build.)
- `android:allowBackup="false"` + `dataExtractionRules` + `fullBackupContent` opt-out.
- `FLAG_SECURE` on the window; content hidden in the app-switcher.
- Release builds: R8 minify + shrink resources + `--obfuscate --split-debug-info`.
- No analytics, no crash reporting, no tracking SDKs.
- Secrets never logged; buffers zeroed after use; secrets not held in widget state.
- `SECURITY.md` documents the threat model.

## 8. Test plan

| Suite | Covers |
|---|---|
| `rfc4226_test` | HOTP official Appendix D vectors |
| `rfc6238_test` | TOTP official vectors, SHA1/256/512, 6/7/8 digits |
| `otpauth_parser_test` | valid + malformed `otpauth://` URIs |
| `migration_parser_test` | `otpauth-migration://offline?data=` incl. malformed input |
| `backup_test` | round-trip, wrong password, corrupted file, unsupported version |
| widget tests | home screen, add-account flow, lock screen |
| `integration_test/` | add → view code → backup → restore (needs a device) |

CI: GitHub Actions — `flutter analyze` + `flutter test` on push/PR.

## 9. Phase order

1. **Plan** ← this document
2. Foundation — project config, theming + dynamic color, routing, secure storage layer
3. Domain — OTP, `otpauth://`, RFC-vector tests
4. Core UI — home, countdown, copy, add-account (QR + manual)
5. Import/export — Google Authenticator migration, `.utaha` backup/restore
6. Security & settings — biometric lock, screenshot block, clipboard clearing, settings
7. Polish — a11y, motion, tablet layout, l10n, icon, splash
8. Release prep — README, SECURITY.md, CI, release config, store listing draft

## 10. Known trade-offs to accept up front

1. **iOS cannot be built or tested here** — no macOS/Xcode on this host. iOS files are kept
   correct and compiling-by-construction, but the first iOS build must happen on a Mac.
2. **No emulator** (no KVM) — integration tests need a physical device over USB/adb.
3. **Argon2id in pure Dart is slow** — mitigated by running it in an isolate with progress UI.
4. **Monochrome/themed icon** needs a vector drawable; `flutter_launcher_icons` generates the
   adaptive layers, the monochrome layer is authored as XML.

---

## 11. Confirmed decisions (Phase 1 sign-off)

| Question | Decision |
|---|---|
| Backup KDF | **Argon2id**, timeCost 3 / memoryCost 64 MiB / parallelism 4, run in an isolate |
| Metadata DB | **drift + drift_flutter** (SQLite), typed DAO, schema migrations |
| Riverpod | **Code generation** — `riverpod_annotation` + `riverpod_generator` + `riverpod_lint` |
| Platforms | **Android (built + tested here) + iOS (source kept correct, first build on a Mac)** |

Format header still records a `kdf_id` byte, so PBKDF2 can be added later without a format break.
