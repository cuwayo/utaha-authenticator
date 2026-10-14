# Store listing draft

Draft copy for Google Play and the App Store. Character limits are noted where
the store enforces one.

---

## Google Play

### App name (30 characters max)

```
Utaha Authenticator
```

### Short description (80 characters max)

```
Offline two-factor codes. No internet, no account, no tracking.
```
*(61 characters)*

### Full description (4000 characters max)

```
Utaha Authenticator generates your two-factor codes without ever going online.

There is no account to create, no sync, and no telemetry. The app requests no
network permission at all — not because it chooses not to connect, but because it
cannot. Your secret keys stay in your device's secure storage and never leave it.

CODES YOU CAN ACTUALLY READ

Large, clearly grouped digits that do not jitter as they tick. A countdown ring
shows how long is left, and turns red in the last five seconds so you know to
wait rather than type a code that is about to expire.

Tap a code to copy it. The clipboard clears itself afterwards — unless you have
copied something else in the meantime, in which case it leaves your clipboard
alone.

Prefer to keep your codes covered? Turn on tap-to-reveal and they stay hidden
until you ask for them.

ADD ACCOUNTS YOUR WAY

Scan the QR code your service shows you, import it from a screenshot, or type the
key in by hand. Bad input is explained plainly — if a character is wrong, the app
tells you which one and where.

MOVING FROM GOOGLE AUTHENTICATOR

Import your entire Google Authenticator export in one go. You see exactly what
will be added before anything is written, including anything that could not be
imported and why.

BACKUPS YOU CONTROL

Export an encrypted file protected with a password only you know, using Argon2id
key derivation and AES-256-GCM. Restore it on a new device. If you would rather
not use a password, there is also a plain-text export — but the app warns you
clearly that it is unprotected, because it is.

PRIVACY BY CONSTRUCTION

• No network permission at all
• No analytics, no crash reporting, no advertising
• Android backup and device transfer disabled, so secrets never reach a cloud
  backup
• Screenshots, screen recording and the recent-apps thumbnail blocked
• Secrets kept in the hardware-backed keystore, never in a plain file

LOCK IT DOWN

Require your fingerprint, face or device PIN to open the app, and choose how long
it may stay in the background before asking again.

LOOKS LIKE YOUR PHONE

Material You design with wallpaper-based colours on Android 12 and later, light
and dark themes, and a true-black mode for OLED screens. A navigation rail on
tablets and foldables. Works with your font size settings, and reads codes out
digit by digit to a screen reader.

FREE AND OPEN SOURCE

MIT licensed, with no paid tier and nothing held back. The two-factor
implementation follows RFC 4226 and RFC 6238 and is tested against the published
test vectors, so you can check the work rather than trust it.
```

### Category

Tools

### Tags

`two-factor`, `2FA`, `authenticator`, `TOTP`, `HOTP`, `security`, `privacy`,
`offline`, `open source`

### Content rating

Everyone

### Data safety declaration

Answer the Play Console questions as follows. These are accurate for the current
build and must be re-checked whenever a dependency is added.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | N/A — no data leaves the device |
| Do you provide a way for users to request that their data is deleted? | Yes — accounts can be deleted in-app, and uninstalling removes all local data |

The app has no network permission, so the "no data collected" answer is
verifiable by inspecting the APK rather than merely asserted.

### Screenshots needed

1. The account list with codes visible.
2. The countdown in its final seconds, showing the error colour.
3. The add-account sheet with the three options.
4. The Google Authenticator import preview.
5. The backup screen.
6. The settings screen showing the security section.
7. The app lock.

Phone screenshots at 1080×1920 or larger. A 7-inch and 10-inch tablet set is also
required if the tablet form factor is claimed.

### Feature graphic

1024×500. Should show the app mark on the brand violet.

---

## App Store

### Name (30 characters max)

```
Utaha Authenticator
```

### Subtitle (30 characters max)

```
Offline 2FA, no tracking
```
*(25 characters)*

### Promotional text (170 characters max)

```
Two-factor codes that never touch the network. No account, no sync, no
telemetry. Encrypted backups you control, and an app lock that keeps your codes
to yourself.
```

### Keywords (100 characters max)

```
2FA,authenticator,TOTP,HOTP,offline,security,privacy,otp,backup,no ads,open source
```

### Description

Reuse the Play full description, with these adjustments:
- Remove "Material You" and "navigation rail" specifics; mention Dynamic Type
  support instead.
- Do not claim screenshot blocking on iOS. It is not implemented. Either omit the
  claim or state that it is Android-only.

### Privacy nutrition label

**Data Not Collected.** The app has no network permission and no analytics SDK.

---

## Review notes

Provide these to reviewers, since an offline app is unusual and reviewers
sometimes flag the absence of network access as a defect:

> This app intentionally requests no network permission. It generates one-time
> passwords locally from secrets stored in the device keystore. It never
> connects to any server, which is the point of the product.
>
> To test: tap **Add account**, choose **Enter a key manually**, and enter any
> name with the key `JBSWY3DPEHPK3PXP`. A six-digit code will appear and refresh
> every 30 seconds.
>
> The camera permission is used only to scan `otpauth://` QR codes. No image ever
> leaves the device.

---

## Pre-release checklist

- [ ] **Replace the app icon and About image with original artwork, or license the
      current art.** This is a legal blocker, not a polish item.
- [ ] Generate a release keystore and fill in `android/key.properties`.
- [ ] Build with `--obfuscate --split-debug-info` and archive the symbols.
- [ ] Run on a real device: camera scan, biometric prompt, screenshot blocking,
      share sheet, file picker.
- [ ] Time an encrypted export and a restore on a mid-range phone; lower the
      Argon2id parameters if it takes more than a few seconds.
- [ ] Capture the screenshots above.
- [ ] Fill in the Data safety form.
- [ ] Decide whether to claim tablet support (requires tablet screenshots).
- [ ] Tag a release and attach the APK and the symbol archive.
