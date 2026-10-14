# R8 / ProGuard rules for Utaha Authenticator.
#
# Release builds run R8 code shrinking. Flutter's Gradle plugin enables it by
# default, and without the rules below it silently removes code that is only
# reached from the Android framework — the kind of removal that cannot be caught
# by compiling or by running the debug build.
#
# Verified against the built release APK: before these rules, `dexdump` showed
# `MainActivity` with an empty virtual-method list, meaning `configureFlutterEngine`
# and `onCreate` had been stripped and the screen-security channel was never
# registered.

# ---------------------------------------------------------------------------
# The app's own activity.
#
# `configureFlutterEngine` and `onCreate` are invoked by the framework, not by
# any code R8 can see, so it considers them unused. Keeping them is what makes
# the FLAG_SECURE channel exist in a release build.
# ---------------------------------------------------------------------------
-keep class moe.nanakura.utaha.MainActivity { *; }

# Any other activity in the app, present or future, is reached only from the
# manifest. Keeping the whole package's activities avoids the same trap being
# reintroduced by a new screen.
-keep public class * extends android.app.Activity
-keep public class * extends androidx.fragment.app.Fragment

# ---------------------------------------------------------------------------
# Plugins that use reflection or JNI.
#
# These are the packages this app actually depends on that need their members
# kept; their own consumer rules cover some of this, but being explicit means a
# future plugin upgrade cannot quietly lose the protection.
# ---------------------------------------------------------------------------

# flutter_secure_storage: reaches into Android Keystore classes reflectively.
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# local_auth: the biometric prompt is invoked through platform channels.
-keep class io.flutter.plugins.localauth.** { *; }

# mobile_scanner / ML Kit: the barcode model classes are constructed by native
# code, which R8 cannot trace.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# ---------------------------------------------------------------------------
# Flutter's own embedding.
#
# Only the entry points the framework calls need keeping. An earlier version of
# this file used a blanket `-keep class io.flutter.**`, which forced R8 to keep
# Flutter's Play Store deferred-components code — that code references Google
# Play classes the app does not depend on, and R8 failed the build outright with
# "Missing classes detected while running R8".
# ---------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter's deferred-components support is not used by this app, but the
# embedding references it unconditionally. Its Google Play dependencies are not
# on the classpath, so R8 is told not to warn about them rather than being made
# to keep code that could never run. These are the rules the Android Gradle
# plugin generated in `missing_rules.txt`.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep annotations, which several of the above read at runtime.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# Keep line numbers so a stack trace from a release build can still be read.
# The Dart side is obfuscated separately via --split-debug-info.
-keepattributes SourceFile,LineNumberTable
