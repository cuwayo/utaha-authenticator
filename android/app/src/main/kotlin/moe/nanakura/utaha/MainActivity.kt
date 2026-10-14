package moe.nanakura.utaha

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's single activity.
 *
 * Extends [FlutterFragmentActivity] rather than `FlutterActivity` because
 * `local_auth` needs a `FragmentActivity` to show its biometric prompt on
 * Android. Using the plain activity compiles and then fails at runtime with
 * "no_fragment_activity", so this is not a cosmetic choice.
 *
 * Also hosts a small method channel for screen-capture protection: Flutter has
 * no API for `FLAG_SECURE`, and without it the account list — a screen full of
 * live one-time codes — would appear in screenshots, screen recordings and the
 * app-switcher thumbnail.
 */
class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val SCREEN_SECURITY_CHANNEL = "moe.nanakura.utaha/screen_security"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        applySecureFlag(true)
                        result.success(true)
                    }
                    "disable" -> {
                        applySecureFlag(false)
                        result.success(true)
                    }
                    "isEnabled" -> result.success(isSecureFlagSet())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Default to blocking capture, before Dart has had a chance to say
        // otherwise. The alternative — starting unprotected and tightening up
        // once the first frame arrives — leaves a window in which the previous
        // session's thumbnail can be captured.
        applySecureFlag(true)
    }

    private fun applySecureFlag(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE,
                )
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    private fun isSecureFlagSet(): Boolean =
        (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
}
