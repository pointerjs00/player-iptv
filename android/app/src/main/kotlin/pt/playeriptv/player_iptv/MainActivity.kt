package pt.playeriptv.player_iptv

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "eTv": Android TV (leanback) ou sem ecrã tátil -> o realce do foco fica sempre ligado
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player_iptv/tv").setMethodCallHandler { call, result ->
            if (call.method == "eTv") {
                val pm = packageManager
                result.success(
                    pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                        !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                )
            } else {
                result.notImplemented()
            }
        }
    }
}
