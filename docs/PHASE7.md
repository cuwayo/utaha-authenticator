# Phase 7 — Polish

Status: **complete**. `flutter analyze` clean, **385 tests passing**, release APK builds
with R8 shrinking, no network permission, and the screen-security code verified present
in the release DEX.

## What was built

| Area | Files |
|---|---|
| Onboarding | `lib/features/onboarding/presentation/onboarding_screen.dart` |
| Accessibility | Row-level semantics in `account_tile.dart`, countdown label, 48dp targets |
| Splash screen | `res/drawable/launch_background.xml`, `values/colors.xml`, `values*/styles.xml` |
| App icon | `tool/generate_icons.sh` (monochrome layer fixed), regenerated icon set |
| Tests | `test/features/accounts/accessibility_test.dart` (22), `test/features/shell/adaptive_layout_test.dart` (6) |

## The release build was broken, and that was the important find

Adding `isMinifyEnabled = true` in Phase 6 made release builds fail outright:

```
ERROR: Missing classes detected while running R8.
Missing class com.google.android.play.core.splitcompat.SplitCompatApplication
  (referenced from: io.flutter.embedding.android.FlutterPlayStoreSplitApplication)
```

The cause was **my own keep rule being too broad**. I had written
`-keep class io.flutter.** { *; }`, which forced R8 to keep Flutter's Play Store
deferred-components code. That code references Google Play classes this app does not
depend on, so R8 could not resolve them and failed the build.

Narrowed to the embedding packages that actually need keeping, plus `-dontwarn` for the
unused deferred-components path. Verified afterwards that the thing the rules exist for
still survives: `screen_security` and `applySecureFlag` are both present in the
R8-processed release DEX.

**Worth noting:** this failed loudly rather than silently, which is the good outcome. The
Phase 6 problem it resembles — R8 stripping `configureFlutterEngine` — was silent.

## Accessibility

The account row previously announced itself as four separate fragments (issuer, account
name, code, countdown), which is unusable when moving through a list with a screen
reader. It now exposes **one coherent label** per row, with `excludeSemantics` on the
children.

Codes are announced **digit by digit** — `1 2 3 4 5 6`, not "one hundred twenty-three
thousand four hundred fifty-six". Asserted by test.

With tap-to-reveal on, the code is **not** in the label; the row announces "hidden"
instead, so the setting is not defeated by a screen reader.

A missing secret announces itself rather than staying silent, and the countdown ring
carries "12 seconds left".

Tests cover: single-label announcement, digit-by-digit spelling, the tap-to-reveal case,
the missing-secret case, the button flag, the countdown label, and 48dp minimum height in
both densities.

## Onboarding

Three pages, skippable at every step, gated on `onboardingCompleted`. The gate renders
nothing until settings load, so someone who already dismissed it never sees a flash of
the introduction.

## Adaptive layout

The 600dp breakpoint is now pinned by tests: bar below, rail above, with a check that a
narrow landscape phone (560×360) keeps the bar rather than eating its little vertical
space with a rail.

## Splash screen

A brand-tinted window (`#EFE9F7` light / `#141018` dark) with the app mark centred, plus
a matching `statusBarColor` so the bar does not flash a different colour during launch.
Deliberately textless — it is on screen for a few hundred milliseconds.

## The monochrome icon is fixed, but still not a real mark

The Phase 6 monochrome layer was a **thresholded greyscale** of the artwork, which
rendered as a black blob. Android tints that layer itself, using only its **opacity** —
so what it wants is a white silhouette on transparency, not a coloured shape.

It is now built as a proper alpha mask (circular crop → white on transparent), so the
themed icon renders as a clean solid disc instead of a blob. Verified visually.

**But it is still not a real mark.** A full-colour illustration has no silhouette, so
the disc is the honest best case. The themed icon will look like a plain circle on
Android 13+. This is inherent to using illustration artwork rather than a designed mark,
and is recorded here rather than presented as solved.

The icon still carries the licensing problem noted in `PHASE2.md`.

## Honest gaps

- **Nothing in this phase has been seen on a device.** The splash screen and the icon
  are verified by inspecting generated files, not by launching the app.
- **Large-font layout is tested only where there are tests.** The onboarding and account
  rows are covered; the settings and backup screens are not.
- **No RTL locale is exercised.** Every string is in `app_en.arb`; there is no
  translation, so `Directionality` behaviour is untested.
- **Animations are limited to the page indicator and the reorder proxy.** The brief asked
  for "smooth, subtle motion" and container transforms for add/edit; those are not built.
- **Predictive back** is enabled via `enableOnBackInvokedCallback`, but the add/edit flows
  are full-screen pushes rather than the suggested container transform.
