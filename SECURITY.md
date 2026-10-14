# Security Policy

## What this app is for

Utaha Authenticator generates one-time passwords from secrets stored on your
device. It is a local tool: it has no server, no account, and no telemetry.

## Reporting a vulnerability

Open a private security advisory on the repository, or email the maintainer
listed on `nanakura.moe`. Please do not open a public issue for a security
problem.

Include what you did, what happened, and what you expected. If the problem
involves a secret, **do not send the secret** — a description is enough.

There is no bug bounty. This is a small project maintained in spare time.

---

## Threat model

### What this app protects against

**A lost or stolen device, locked.** Secrets live in the platform keystore, not
in a file. Someone who picks up the phone cannot read them without the device
credential, and the app lock adds a second gate in front of the codes.

**Shoulder-surfing and screenshots.** Tap-to-reveal keeps codes covered by
default, and `FLAG_SECURE` blocks screenshots, screen recording and the
app-switcher thumbnail.

**A device backup leaking.** Android's own backup and device-transfer are
disabled outright, so secrets are never uploaded to a cloud backup by the OS.

**A stolen backup file.** Backups are encrypted with a key derived from the
user's password using Argon2id, and authenticated with AES-256-GCM. Without the
password the file is not readable, and any modification to it is detected.

**A malicious QR code.** Scanned URIs are validated strictly: an unknown
algorithm, an unsupported digit count, or a malformed secret is rejected with an
explanation rather than silently producing wrong codes.

**A malicious backup file.** KDF parameters are bounded before any work is done,
so a file cannot make the app allocate gigabytes or hang.

### What this app does NOT protect against

**A rooted or jailbroken device.** On a rooted device, another process with
sufficient privilege can read the keystore, the app's memory, or both. The app
lock is a UI gate, not a cryptographic one.

**A compromised operating system.** If the OS itself is hostile, nothing an app
does is meaningful.

**A user who chooses a weak backup password.** Argon2id makes guessing
expensive, but it cannot rescue `password123`. The app warns that the password
cannot be recovered, but it cannot assess strength.

**Screenshots taken by a rooted device or a screen-recording app with elevated
permissions.** `FLAG_SECURE` is enforced by the OS and can be bypassed by the OS
itself.

**Malware with accessibility-service permissions.** Such an app can read the
screen and drive the UI, including the codes and the unlock prompt.

**An attacker who can observe the device at the moment of use.** If someone can
see the screen or the unlocked device, no amount of storage protection helps.

### Explicitly out of scope

- Physical coercion.
- Supply-chain attacks on the Flutter toolchain or the platform.
- Compromise of a service the user has accounts with.

---

## How secrets are handled

### Where secrets live

| Data | Where | Protection |
|---|---|---|
| OTP secret keys | Android Keystore / iOS Keychain | Hardware-backed encryption |
| Account metadata (issuer, name, tags) | SQLite | Not secret; not encrypted |
| Settings | SQLite | Not secret |
| Backup password | Never stored | Held in memory for one operation |

**Metadata is deliberately not encrypted.** Issuer and account names are not
credentials, and encrypting them would make search and ordering impractical while
adding little: an attacker with the device unlocked already has the codes.

### What is never done

- Secrets are **never** written to `SharedPreferences`, a plain file, a log, a
  crash report, or an analytics service.
- The app **never** has network permission. The release APK is built with
  `INTERNET` and `ACCESS_NETWORK_STATE` explicitly removed, so even a future
  plugin cannot silently reintroduce them — the build fails instead.
- No third-party analytics, advertising or tracking SDK is included.
- Secrets are **never** displayed in an import preview, a settings screen, or any
  list. The edit form starts with the secret field blank so the stored key is
  never loaded into a widget.

### Zeroing

Secrets are handled as `Uint8List` and overwritten with zeros as soon as they are
no longer needed — after generating a code, after writing to the keystore, and
after an export or import completes.

**This is best-effort, and the limitation is real.** Dart `String` values are
immutable and may be copied or interned by the runtime, so a secret that arrives
as text (a Base32 key pasted from a QR code) cannot be reliably wiped. The
mitigation is to convert to bytes as early as possible and keep the string's
lifetime short. `lib/core/utils/zeroing.dart` documents this at the source.

Zeroing also cannot defeat an attacker who can already read the process's memory.
It raises the cost of a heap dump; it is not a guarantee.

---

## Backup file format

```
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

- **KDF:** Argon2id, 3 iterations, 64 MiB memory, 32-byte key. The parameters are
  recorded in every file, so raising them later does not invalidate existing
  backups.
- **Cipher:** AES-256-GCM.
- **The header is authenticated as additional data**, so tampering with the
  version, KDF parameters, salt or nonce fails the authentication check rather
  than changing how the ciphertext is interpreted.
- A fresh random salt and nonce are used for every file. Reusing either would
  break GCM's guarantees outright; this is asserted by test.
- A wrong password and a tampered file are **indistinguishable** by design,
  because saying which would leak whether the ciphertext authenticated.

### The unencrypted export

The app can also write a plain list of `otpauth://` URIs. That output is **not
protected in any way** — anyone who obtains it can generate codes for every
account. It requires two confirmations and is styled as destructive. It exists
because some people need to move accounts to a tool that reads only `otpauth://`.

---

## Android-specific configuration

- `android:allowBackup="false"` with explicit `dataExtractionRules` and
  `fullBackupContent` excluding every domain.
- `FLAG_SECURE` is applied in `MainActivity.onCreate`, before Dart runs, so the
  app is never briefly capturable at launch.
- Release builds run R8 with explicit keep rules. Without them R8 strips the
  activity methods the framework calls and the screen protection silently stops
  working — see the comment in `android/app/proguard-rules.pro`.
- The only permissions requested are `CAMERA` (scanning) and the biometric ones.
  There is no network permission at all.

## iOS

- Keychain accessibility is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so
  secrets are not migrated to a new device by an iCloud backup.
- **Screen-capture blocking is not implemented on iOS.** The Android approach has
  no direct equivalent; the iOS technique uses a `UITextField`-based trick that
  this build does not include. Calls are no-ops there. This is a real gap, not an
  oversight.

---

## Artwork

The launcher icon and About-screen image are third-party character artwork, not
original works. They are excluded from the MIT licence — see `LICENSE`.

**This must be resolved before any public release.** Distributing third-party
character art without a licence exposes the project to a takedown and a claim.
Replacing it is a one-command change; see the note in `LICENSE`.

The Android 13+ themed (monochrome) icon is derived from that artwork and renders
as a plain disc, because a full-colour illustration has no silhouette. That is
inherent to the artwork, not a bug in the generator.

---

## Dependencies

The app depends on well-maintained packages, but each is code that runs with
access to secrets. `pubspec.lock` is committed so builds are reproducible.

Notable choices, and why:

- **`flutter_secure_storage`** for secrets — the platform keystore, not a file.
- **`cryptography`** for Argon2id and AES-GCM — pure Dart, so the crypto is
  auditable and behaves identically on both platforms.
- **No `otp` package.** RFC 4226 and RFC 6238 are implemented directly and proven
  against the published test vectors, so the code path is visible.
- **No analytics, crash reporting, or advertising SDK of any kind.**
