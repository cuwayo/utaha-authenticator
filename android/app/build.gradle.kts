import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from `android/key.properties` when it exists.
//
// That file and the keystore it points at are gitignored and must never be
// committed. When it is absent — a fresh clone, or CI without secrets — the
// release build falls back to the debug key so `flutter run --release` and the
// CI build check still work. The fallback is flagged below because it must not
// be used for a published build.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "moe.nanakura.utaha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "moe.nanakura.utaha"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // Both schemes: v2+ is required for modern Android, and v1 keeps
                // older devices installable.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Fail rather than fall back to the debug key.
                //
                // A debug-signed release build is a real hazard: it installs
                // fine and looks fine, so nothing tells you it cannot be
                // published until the store rejects it. A warning is not enough,
                // because Gradle's configuration-phase output is filtered out of
                // Flutter's build log and nobody sees it.
                //
                // Pass `-PallowDebugSigning=true` to opt in explicitly — which
                // CI does, since it builds a release APK to check that R8 and the
                // permission list are still correct.
                // Read from a Gradle property or an environment variable.
                //
                // The environment variable matters: `flutter build apk` does not
                // forward `-P` properties to Gradle, and calling `./gradlew`
                // directly skips the step where Flutter compiles plugin Android
                // modules — so `integration_test` (a dev dependency) is left
                // unreferenced and the build fails on
                // GeneratedPluginRegistrant.java. Going through `flutter build`
                // with an env var is the only path that works end to end.
                val allowDebugSigning =
                    (project.findProperty("allowDebugSigning") as String?) == "true" ||
                        System.getenv("UTAHA_ALLOW_DEBUG_SIGNING") == "true"
                if (!allowDebugSigning) {
                    throw GradleException(
                        "\n" +
                            "Release signing is not configured.\n" +
                            "\n" +
                            "  android/key.properties is missing, so this build would be\n" +
                            "  signed with the debug key and could not be published.\n" +
                            "\n" +
                            "  To fix it properly, copy android/key.properties.example to\n" +
                            "  android/key.properties and fill it in.\n" +
                            "\n" +
                            "  To build anyway — for a local test, or for CI that only\n" +
                            "  checks the release build compiles — set:\n" +
                            "\n" +
                            "    UTAHA_ALLOW_DEBUG_SIGNING=true flutter build apk --release\n" +
                            "\n" +
                            "  Do not publish the result.\n",
                    )
                }
                logger.lifecycle(
                    "Signing the release build with the DEBUG key " +
                        "(allowDebugSigning=true). Do not publish this artifact.",
                )
                signingConfig = signingConfigs.getByName("debug")
            }

            // Shrink and obfuscate. The rules in proguard-rules.pro are not
            // optional: without them R8 strips the activity methods that the
            // framework calls, and the screen-capture protection silently stops
            // working in release builds. See the comment in that file.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // No shrinking while developing, so stack traces stay readable.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
