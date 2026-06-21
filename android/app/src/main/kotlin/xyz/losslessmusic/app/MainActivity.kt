package xyz.losslessmusic.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import xyz.losslessmusic.backend.bridge.Bridge

class MainActivity : FlutterActivity() {
    private val channel = "xyz.losslessmusic/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(Bridge.ping())
                    "getDownloadProgress" -> result.success(Bridge.getDownloadProgress())
                    else -> result.notImplemented()
                }
            }
    }
}
