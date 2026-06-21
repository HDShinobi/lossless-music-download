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
                try {
                    when (call.method) {
                        "ping" -> result.success(Bridge.ping())
                        "getDownloadProgress" -> result.success(Bridge.getDownloadProgress())
                        "initExtensionSystem" -> {
                            Bridge.initExtensionSystem(
                                call.argument<String>("extDir")!!,
                                call.argument<String>("dataDir")!!
                            )
                            result.success(null)
                        }
                        "loadExtensionFromPath" -> result.success(
                            Bridge.loadExtensionFromPath(call.argument<String>("path")!!)
                        )
                        "getInstalledExtensions" -> result.success(Bridge.getInstalledExtensions())
                        "setExtensionEnabled" -> {
                            Bridge.setExtensionEnabledByID(
                                call.argument<String>("id")!!,
                                call.argument<Boolean>("enabled")!!
                            )
                            result.success(null)
                        }
                        "removeExtension" -> {
                            Bridge.removeExtensionByID(call.argument<String>("id")!!)
                            result.success(null)
                        }
                        "searchTracks" -> result.success(
                            Bridge.searchTracksWithMetadataProvidersJSON(
                                call.argument<String>("query")!!,
                                (call.argument<Int>("limit") ?: 20).toLong(),
                                call.argument<Boolean>("includeExtensions") ?: true
                            )
                        )
                        "downloadByStrategy" -> result.success(
                            Bridge.downloadByStrategy(call.argument<String>("requestJson")!!)
                        )
                        "getAllProgress" -> result.success(Bridge.getAllDownloadProgress())
                        "cancelDownload" -> {
                            Bridge.cancelDownload(call.argument<String>("itemId")!!)
                            result.success(null)
                        }
                        "setDownloadDirectory" -> {
                            Bridge.setDownloadDirectory(call.argument<String>("path")!!)
                            result.success(null)
                        }
                        "allowDownloadDir" -> {
                            Bridge.allowDownloadDir(call.argument<String>("path")!!)
                            result.success(null)
                        }
                        "checkDuplicate" -> result.success(
                            Bridge.checkDuplicate(
                                call.argument<String>("outputDir")!!,
                                call.argument<String>("isrc")!!
                            )
                        )
                        "getExtensionSettings" -> result.success(
                            Bridge.getExtensionSettingsJSON(call.argument<String>("id")!!)
                        )
                        "setExtensionSettings" -> {
                            Bridge.setExtensionSettingsJSON(
                                call.argument<String>("id")!!,
                                call.argument<String>("settingsJson")!!
                            )
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("BACKEND_ERROR", e.message, null)
                }
            }
    }
}
