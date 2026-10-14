# Phase 4b — Add-account flows

Status: **complete**. `flutter analyze` clean, **210 tests passing**, release APK builds
with no network permission.

## What was built

| File | Purpose |
|---|---|
| `lib/domain/services/account_importer.dart` | URI/manual import, duplicate detection |
| `lib/features/scan/presentation/scan_screen.dart` | Camera QR scanning |
| `lib/features/scan/presentation/manual_entry_screen.dart` | Typed entry + editing |
| `lib/features/scan/presentation/add_account_sheet.dart` | The three-way chooser, image import |
| `test/domain/services/account_importer_test.dart` | 24 tests |
| `test/features/scan/manual_entry_screen_test.dart` | 14 tests |

The three ways in — camera, saved image, typed — all funnel through one
`AccountImporter`, so duplicate handling and error reporting behave identically
whichever route the user takes.

## Duplicate handling

Adding an account that already exists is **not an error**. It is sometimes
deliberate (two accounts for one service, or re-adding after a keystore reset), so
the importer reports `ImportDuplicate` and the UI asks, offering "Add anyway".

Matching is case-insensitive and trims whitespace, because the same account scanned
twice rarely differs by more than spacing. Two subtleties that needed explicit
handling:

- **An account is not a duplicate of itself.** When editing, `replaceExistingId`
  excludes that account from the collision check.
- **"Add anyway" needed a `force` flag.** Without one, re-running the import after
  the user confirmed would hit the same duplicate check and ask again, forever.

## Bugs found and fixed while building this

1. **A zeroed-secret bug that would have stored a broken key.** `importManual`
   originally zeroed the caller's buffer before returning. But the duplicate-retry
   path reuses that buffer, so "Add anyway" would have stored an all-zero secret —
   producing an account that looks fine and generates wrong codes. The importer no
   longer zeroes the caller's buffer; ownership is documented, and the screen wipes
   it in a `finally` after the whole flow (including any retry) has finished. Pinned
   by a test that asserts the buffer is still non-zero after the call.
2. **An infinite loop in "Add anyway."** The first implementation re-ran the import,
   which re-detected the duplicate and prompted again. Fixed with `force`.
3. **A placeholder-secret edit path.** I briefly built the metadata-only edit by
   synthesising an `otpauth://` URI with `secret=PLACEHOLDER`, which could never
   parse. Replaced with a direct `updateMetadata` call that never touches the secret
   store, so a rename cannot possibly leave an account without a usable key.
4. **A hand-rolled `WidgetRef` adapter.** I wrote a `_ContainerRef` class to let a
   plain function read providers. That is fragile — `WidgetRef` is not an interface
   to reimplement. Removed it and passed the real `ref` through.

## Design decisions worth noting

**The stored secret is never loaded into a text field.** When editing, the secret
field starts blank with the hint "Leave this blank to keep the current key". This
means the key cannot leak into the widget tree, a keyboard buffer, or a screenshot
of the edit form — and it means renaming an account does not require re-entering a
key. Tested.

**The camera is stopped as soon as a code is recognised**, so a second scan cannot
fire while the confirmation sheet is open and the camera is not left running behind
it. It restarts if the user declines.

**Only QR format is requested.** Narrowing the scanned formats makes detection
faster and less prone to false positives.

**Image import uses the system photo picker**, so the app receives only the single
image the user chose rather than browsing their library.

**Secrets are zeroed on every path.** The screen owns the decoded buffer and wipes
it in a `finally`; the URI path wipes the parsed buffer in its own `finally`.

## Test-infrastructure note

The manual-entry widget tests initially failed en masse because the form is a lazy
`ListView`: fields below the fold do not exist in the widget tree. Rather than making
every test scroll, they now pump into a viewport tall enough to build the whole form.
That removes a whole class of "widget does not exist yet" failures and keeps the tests
about validation rather than about scrolling.

## Carried forward

- Scanning needs a physical device or emulator to exercise for real — this host has
  no KVM, so the camera path is unit-tested at the importer level but has never run
  against a live camera. **This is the largest untested surface in the app.**
- Image import depends on `MobileScannerController.analyzeImage`, which needs a real
  platform channel; likewise untested on-device.
- Tags are stored and searchable but there is no tag editor yet.
- The `otpauth-migration://` (Google Authenticator) import and encrypted backup are
  Phase 5.
