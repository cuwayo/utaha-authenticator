# Phase 3 — Domain

Status: **complete**. `flutter analyze` clean, **126 tests passing** (90 of them domain tests),
release APK still builds.

## What was built

| File | Purpose |
|---|---|
| `lib/domain/otp/otp_algorithm.dart` | SHA1 / SHA256 / SHA512 enum, tolerant URI-name parsing |
| `lib/domain/otp/otp_type.dart` | TOTP / HOTP enum |
| `lib/domain/otp/otp.dart` | RFC 4226 HOTP + RFC 6238 TOTP, countdown helpers |
| `lib/domain/otpauth/otpauth_uri.dart` | `otpauth://` parse + build |
| `lib/domain/models/account.dart` | Account model — **deliberately holds no secret** |
| `test/domain/otp/rfc4226_test.dart` | RFC 4226 Appendix D vectors |
| `test/domain/otp/rfc6238_test.dart` | RFC 6238 Appendix B vectors |
| `test/domain/otpauth/otpauth_uri_test.dart` | Parser/serialiser, valid + malformed |

## Vectors verified against the RFCs themselves

Both RFC texts were downloaded and the tables extracted from them rather than
reproduced from memory.

**RFC 4226 Appendix D** — secret `"12345678901234567890"` (20 bytes). All ten
published HOTP values reproduce exactly:

```
counter 0..9 → 755224 287082 359152 969429 338314 254676 287922 162583 399871 520489
```

**RFC 6238 Appendix B** — all 18 published values reproduce for SHA1, SHA256 and
SHA512 at t = 59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000.

### The RFC 6238 erratum, handled explicitly

The RFC's prose says all algorithms use the 20-byte ASCII secret, but its
published SHA-256 and SHA-512 values do **not** — they use the ASCII string
repeated to 32 and 64 bytes. This is RFC 6238 errata ID 2866.

Implemented correctly and pinned down by a test, so the choice is deliberate
rather than accidental:

- `test('the 20-byte secret does NOT reproduce the SHA-256 vectors')`
- `test('the 20-byte secret DOES reproduce the SHA-1 vectors')`

## Behaviour worth knowing

**Padding is a correctness requirement.** A code that truncates to a small
integer must render as `07081804`, not `7081804`. Without left-padding the app
would show a plausible-looking but wrong code. Asserted directly.

**The counter is encoded big-endian by hand.** `ByteData.setUint64` cannot be
used because Dart's `int` is signed on native platforms, so the unsigned top half
of a 64-bit value is not representable. Shifting byte by byte keeps the encoding
correct across the whole `int` range.

**Dynamic truncation works for any digest length.** The offset comes from the low
nibble of the final byte, so SHA-256 and SHA-512 need no special-casing — the
same four-byte window logic applies.

**Countdown helpers are clamped.** `totpSecondsRemaining` can never return 0 or
`period + 1`, and `totpProgress` is clamped to `0.0..1.0`, so sub-second jitter
cannot surface as a visibly wrong number in the UI.

**`Account` holds no secret.** The secret lives only in the keystore, addressed
by `Account.id`. This makes it structurally impossible for a log line, a JSON
dump or a crash report to carry a secret, because the model has nothing to leak.
`toString()` is overridden and documents this.

**`Account.tags` is defensively copied** into an unmodifiable list, because the
class is `@immutable` and defines `==`/`hashCode` — a caller-owned mutable list
could otherwise change an object's hash while it sat in a `Set` or `Map`.

## `otpauth://` parsing decisions

Parsing is **forgiving about presentation, strict about content**:

- Case-insensitive scheme, host and parameter names (`SECRET=`, `TOTP`).
- Accepts `SHA1`, `sha1`, `SHA-1` and `sha_1`.
- Accepts secrets written in groups: `JBSW Y3DP EHPK 3PXP`.
- Rejects a secret containing a character outside the Base32 alphabet, and says
  *which* character and *where* — silently dropping it would produce a wrong code.
- Rejects an HOTP URI with no `counter`, rather than defaulting to 0 and
  generating a code the server would reject.
- Never includes the secret in an error message (asserted by test).

### Two format ambiguities, documented rather than hidden

1. **A colon inside a label part.** The label is decoded, *then* split on its
   first colon — which is what every mainstream authenticator does, and what
   makes the common fully-encoded form `My%20Company%3Aada%40example.com` parse
   correctly. The unavoidable consequence is that `%3A` inside a part is
   indistinguishable from the separator. Both behaviours are pinned by tests.

2. **An issuer containing a colon** still round-trips, because `build()` emits the
   issuer as a query parameter *as well as* a label prefix, and the parameter is
   authoritative. `parse()` strips the prefix from the label before using it as
   the account name, so the mis-split prefix cannot leak into the account name.

## Bugs found and fixed while testing

- `library;` was placed after the imports in `otp.dart` — a compile error.
- Inside `OtpAlgorithm`, bare `sha1` resolved to the *enum member* rather than
  `crypto.sha1`, so `hash` returned the wrong type. Fixed with a prefixed import.
- `account.dart` imported the OTP enums from the wrong directory.
- `_decodeLabel` caught `ArgumentError`, which the analyzer correctly flags as
  catching an `Error` rather than an `Exception`; `Uri.decodeComponent` throws
  `FormatException`.
- Three of my own test assertions were wrong (a reversed period-boundary
  expectation, an incorrect progress/remaining relationship, and a wrong
  assumption about issuer round-tripping). Each was verified against the RFC
  text or the actual behaviour before being corrected — the implementation was
  right and the tests were wrong in all three cases.

## Carried forward

- `Account` is not yet persisted; the drift schema and repositories arrive with
  the account list in Phase 4.
- `totpProgress`/`totpSecondsRemaining` are ready for the countdown indicator.
- `OtpAuthUri.build` exists for Phase 5's plain-text export (with the unencrypted
  warning).
