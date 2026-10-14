# Icon fix: the empty vector foreground

## Symptom

The launcher showed Android's built-in fallback icon — a teal circle with a
white robot — instead of the app's artwork. The app itself worked perfectly.

## What was ruled out, with evidence

Every one of these was checked and was **correct**:

| Checked | Result |
|---|---|
| `android:icon` / `android:roundIcon` in the manifest | Point at `mipmap/ic_launcher` / `ic_launcher_round` |
| Legacy `ic_launcher.png` at all 5 densities, extracted from the APK | Character art |
| `ic_launcher_background.png` at all 5 densities | Character art |
| `ic_launcher_round.png` at all 5 densities | Character art |
| The compiled adaptive-icon XML (`res/BW.xml`, `res/0K.xml`) | `background`/`foreground`/`monochrome` all reference the right resources |
| The APK on the device vs the one on the build host | Byte-identical md5 |
| Launcher icon cache | Cleared, launcher force-stopped, device rebooted — no change |
| Themed icons / icon packs | Not enabled on this device |

So the artwork was present and referenced correctly, and the launcher was still
drawing the default. That is the signature of **icon inflation failing**, which
makes a launcher silently fall back.

## Cause

`drawable/ic_launcher_foreground.xml` was written as a `<vector>` with **no
`<path>` child**:

```xml
<vector android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108" />
```

The intent was "an empty layer, so nothing is drawn over the art" — the artwork
is carried entirely by the background layer. But a vector with no paths is not a
valid drawable, and inflating it fails. When the foreground layer of an
`<adaptive-icon>` fails to inflate, the launcher discards the whole icon and
substitutes its default.

The failure is silent: nothing is logged, the app installs and runs fine, and the
only visible symptom is the wrong picture.

## Fix

One transparent path, so the layer is valid and draws nothing:

```xml
<vector android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#00000000"
        android:pathData="M0,0h108v108h-108z" />
</vector>
```

## Verified

After rebuilding and installing, the launcher shows the character artwork.
Confirmed by screenshot on the Redmi Note 5A (Android 16).

## A second bug found while fixing this

The build failed with:

```
GeneratedPluginRegistrant.java:49: error:
  package dev.flutter.plugins.integration_test does not exist
```

Cause: `integration_test` is a dev dependency, and running `./gradlew` directly
**skips the step where Flutter compiles plugin Android modules**. The generated
registrant then references a plugin that was never built.

This mattered because the release-signing guard added in Phase 8 told the reader to
build with `./gradlew -PallowDebugSigning=true`. That instruction was wrong, and
it was written into both the error message and CI.

Fixed by moving the opt-in to an **environment variable**
(`UTAHA_ALLOW_DEBUG_SIGNING=true`) so the build can go through `flutter build apk`,
which runs the plugin compilation. CI was updated to match.

Worth noting the guard itself worked: it refused to produce a debug-signed release
build until asked, and the failure surfaced loudly rather than shipping a broken
artifact.

## Lesson

An empty XML element is not the same as a transparent one. `-keep`-style
"do nothing" placeholders still have to be *valid* for their schema — a lesson
that already cost time once in this project, with the R8 keep rules.
