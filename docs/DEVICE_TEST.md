# First device test

**Date:** 2026-10-14
**Device:** Redmi Note 5A (`lineage_Mi8937_4_19`, `ugglite`), Android 16 / API 36, arm64-v8a
**Build:** release APK, R8-shrunk, signed with the debug key
**Install:** `adb install -r` → `Success`

This is the first time the app has run on real hardware. Every earlier phase was
verified by tests and by inspecting build artifacts; nothing had been executed.

---

## What was verified, and how

| Claim | Evidence | Result |
|---|---|---|
| The app launches and does not crash | `pidof` non-zero throughout; **0** `FATAL EXCEPTION` entries for our package | Pass |
| `FLAG_SECURE` blocks screen capture | `SurfaceFlinger` shows every layer as **`(Secure)`** | **Pass** |
| A real TOTP code is generated | Phone showed `388719`; an independent RFC 6238 computation at the same time step returned `388719` | **Pass** |
| The secret reaches the Android Keystore | The Base32 text appears **nowhere** in `/data/data/moe.nanakura.utaha/` | Pass |
| Metadata persists to SQLite | Added an account; it survived and re-rendered | Pass |
| `local_auth` shows a prompt | Device-credential sheet appeared with our exact string | **Pass** |
| `MainActivity` is a `FragmentActivity` | The prompt rendered instead of throwing `no_fragment_activity` | **Pass** |
| The lock refuses to enable without authentication | Cancelled the prompt → switch stayed `checked=false` | **Pass** |
| Accessibility labels are correct | `content-desc` reads `GitHub, ada@example.com, 3 1 9 0 4 6, 6 seconds left` | Pass |
| Digit-by-digit code announcement | The comma-separated digits above are the `_semanticLabel` output | Pass |
| Empty state, add sheet, manual form all render | Dumped each screen's hierarchy | Pass |
| The secret field is masked | Field renders `••••••••••••••••` | Pass |

### The screenshot result is the interesting one

`screencap` returned an entirely black image, and a second capture of a different
app was **byte-identical** — so the control test was invalid and proved nothing.
The real evidence came from `dumpsys SurfaceFlinger`:

```
Layer [3940] (Secure) moe.nanakura.utaha/moe.nanakura.utaha.MainActivity
Layer [3944] (Secure) SurfaceView[moe.nanakura.utaha/MainActivity]
```

Every layer marked `(Secure)` is `FLAG_SECURE` doing its job. This is the one
feature that **cannot** be verified any other way: no unit test, no analyzer run
and no code inspection can show that the OS refuses to capture the window.

### The code match

```
step 59732832
  phone shows:   388719
  RFC 6238 says: 388719
```

The comparison was taken in a single time step, retrying if the step rolled over
mid-read — otherwise the two would differ by construction and the test would be
meaningless.

This closes the whole chain on real hardware: keystore → secret → HMAC-SHA1 →
dynamic truncation → six digits on screen.

---

## A false alarm worth recording

The Add-account button reported `enabled="false"`, which looked like a bug. It was
not: only two of the three text fields had received input, because `adb input
tap` landed on the wrong rows, so the required account name was empty and
validation correctly blocked submission.

The app was right and the test was wrong. Worth writing down because the
symptom — a disabled button — is exactly what a real validation bug would look
like.

---

## Still not verified

- **Camera scanning.** The permission prompt appeared and was granted, but no QR
  code was scanned. This remains the largest untested surface.
- **The unlock path.** The device-credential prompt was cancelled rather than
  completed, because the PIN is not known to the test. So the *lock* is proven to
  engage correctly; the *unlock* is not proven to succeed.
- **Clipboard contents.** Android 10+ blocks a background app from reading the
  clipboard, and `adb shell service call clipboard` is not usable here. A
  `clipboard overlay` line in logcat suggests the system confirmation appeared,
  but that is weak evidence. Not claimed.
- **Backup export and restore.** The UI renders; the flow was not run.
- **Google Authenticator import.** Not exercised with a real export.
- **Screenshot blocking on iOS.** Not implemented, so nothing to test.
- **`pruneOrphanedSecrets` at startup.** Still not wired in.

---

## Incidentals

- **183 frames skipped on first launch.** JIT warm-up on a 2017 low-end phone with
  a 79 MB R8'd APK. Subsequent interaction was smooth.
- The app survived being backgrounded, the app switcher, a photo-picker launch and
  repeated back navigation without a single crash.
