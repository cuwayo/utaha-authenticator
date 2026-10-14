# Phase 5 — Import and export

Status: **complete**. `flutter analyze` clean, **325 tests passing**, release APK builds
with no network permission.

## What was built

| File | Purpose |
|---|---|
| `proto/otp_migration.proto` | The reconstructed Google Authenticator export schema |
| `tool/generate_migration_vectors.py` | Generates test vectors with real `protoc` |
| `test/fixtures/migration_vectors.yaml` | Generated vectors (8 cases) |
| `lib/domain/migration/google_auth_migration.dart` | `otpauth-migration://` parser |
| `lib/domain/backup/backup_format.dart` | The `.utaha` layout and Argon2id parameters |
| `lib/domain/backup/backup_codec.dart` | Argon2id + AES-256-GCM encrypt/decrypt |
| `lib/domain/backup/backup_payload.dart` | The JSON body carried inside a backup |
| `lib/domain/backup/backup_service.dart` | Export, restore, plain-text export |
| `lib/features/backup/presentation/backup_screen.dart` | The backup UI |
| `lib/features/backup/presentation/migration_screen.dart` | Scan/paste, preview, confirm |
| `lib/features/backup/presentation/backup_dialogs.dart` | Password prompt, progress, errors |

## The `.utaha` format

```text
offset  size  field
0       5     magic, ASCII "UTAHA"
5       1     format version
6       1     kdf id
7       1     kdf parameter block length
8       n     kdf parameters
8+n     16    salt
24+n    12    nonce
36+n    ...   ciphertext || 16-byte GCM tag
```

The header is passed to AES-GCM as **additional authenticated data**, so tampering
with the version, KDF parameters, salt or nonce fails the tag check rather than
silently changing how the ciphertext is interpreted. Each of those is covered by a
test that flips one byte and asserts rejection.

The version byte and KDF id mean the format can evolve: PBKDF2 can be added later
without breaking files written today, and the parameters are recorded per file so
raising the defaults does not invalidate existing backups.

**Defaults:** Argon2id, 3 iterations, 64 MiB, 32-byte key. Deliberately expensive —
a backup file is the one artefact that leaves the device, so it is the one place an
attacker can attack offline with unlimited attempts.

## Two serious bugs, both caught by tests

Both were the same class of mistake — **zeroing a buffer while something still
pointed into it** — and both would have produced silently broken accounts.

### 1. Every password derived the same key

`_deriveKey` returned its future from inside a `try`/`finally`, so the `finally`
zeroed the password bytes *before* Argon2id read them. The KDF then hashed zeros,
producing an identical key for every password — **any password would open any
backup**. It was intermittent (scheduling-dependent), which is how it survived a
first read.

Fixed by making the helper `async` and awaiting the derivation before the `finally`
runs. There are now three deterministic regression tests using a fixed salt and
nonce, including one that repeats the wrong-password attempt eight times.

### 2. Every imported account would have had an all-zero secret

`readLengthDelimited` returned a **view** into the payload buffer. The parser zeroes
that buffer in a `finally`, so the secrets were wiped along with it — every account
imported from Google Authenticator would have had a zero key and generated wrong
codes.

Fixed by returning copies for retained values, with a separate non-copying reader
for nested messages that are consumed immediately. The comment on the method says
why, because it is an easy mistake to reintroduce.

## Testing the migration parser against real protobuf

The schema is an unofficial reconstruction, so guessing it was not acceptable. I
found it cross-referenced from three independent sources and Google's own issue
tracker, then wrote it into `proto/otp_migration.proto`.

Two details that are easy to get wrong, both confirmed:
- `digits` is an **enum** (`DigitCount`), not an integer.
- `type` is an enum where **HOTP = 1, TOTP = 2** — note the order.

`tool/generate_migration_vectors.py` runs `protoc --encode` to produce real wire
bytes, which are committed as fixtures. The tests then assert the parser reads them
back to exactly the input — including the raw secret bytes, which guards against an
off-by-one in the varint or length reader. I verified independently that `protoc
--decode` round-trips the same vectors.

The protobuf is decoded by hand rather than with generated code: the schema is five
fields and two levels deep, and the Dart `protoc` plugin is not in this toolchain.
A small, heavily-tested reader is a better trade than a codegen step and a dependency.

## Behaviour worth noting

- **Unusable entries are reported, not silently dropped.** An entry with an empty
  secret, an unsupported algorithm, or MD5 is skipped with a plain-language reason
  shown in the preview sheet. A silent partial import is how people lose an account
  without noticing.
- **Unknown protobuf fields are skipped**, so a future Google Authenticator adding a
  field does not break imports.
- **A mangled display name does not cost the user their account** — invalid UTF-8 is
  replaced rather than rejecting the entry.
- **Hostile KDF parameters are bounded** before any work happens; a file claiming
  4 GiB of memory is rejected rather than hanging the device.
- **Wrong password and tampered file are indistinguishable** by design, since saying
  which would leak whether the ciphertext authenticated.
- **The plain-text export needs two confirmations** and is styled as destructive. Its
  output is unprotected and the warning says so plainly.
- **Secrets are never rendered in the preview sheet**, even though it lists accounts.

## Honest gaps

- **The backup UI has not been driven end to end on a device.** The domain layer is
  thoroughly tested, but the screens (file picker, share sheet, camera) need real
  platform channels. `file_picker` 13 turned out to be a reworked API and I fixed the
  call sites against its source, not against a running app.
- **Argon2id with the production defaults has never been timed on a phone.** The
  parameters are recorded per file so they can be tuned down if it proves too slow,
  but the actual wall-clock cost is unmeasured.
- Restoring does not de-duplicate by issuer+name, only by id. A backup restored onto
  a device that already has the same accounts under different ids will duplicate them.

## Carried forward

- The lock screen, biometrics and screenshot blocking are Phase 6.
- `pruneOrphanedSecrets` is implemented and tested but still not called at startup.
