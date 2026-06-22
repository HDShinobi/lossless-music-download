package xyz.losslessmusic.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import xyz.losslessmusic.backend.bridge.Bridge

class MainActivity : FlutterActivity() {
    private val channel = "xyz.losslessmusic/native"

    // Held while the DLNA MediaServer runs so SSDP multicast can be received.
    private var multicastLock: WifiManager.MulticastLock? = null

    // Bridge calls do blocking I/O (network search/download, file probing, server
    // start). Running them on the platform main thread blocks the UI and causes
    // ANRs, so they run on this pool and reply on the main thread. A pool (not a
    // single thread) lets progress polling run while a long download is in flight.
    private val bridgeExecutor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                bridgeExecutor.execute {
                    try {
                        val (handled, value) = dispatch(call)
                        mainHandler.post {
                            if (handled) result.success(value) else result.notImplemented()
                        }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("BACKEND_ERROR", e.message, null) }
                    }
                }
            }
    }

    // Runs on a background thread. Returns (handled, value); the caller posts the
    // result on the main thread.
    private fun dispatch(call: MethodCall): Pair<Boolean, Any?> = when (call.method) {
        "ping" -> true to Bridge.ping()
        "getDownloadProgress" -> true to Bridge.getDownloadProgress()
        "getAudioQuality" -> true to Bridge.getAudioQualityJSON(call.argument<String>("path")!!)
        "initExtensionSystem" -> {
            Bridge.initExtensionSystem(
                call.argument<String>("extDir")!!,
                call.argument<String>("dataDir")!!
            )
            true to null
        }
        "loadExtensionFromPath" -> true to Bridge.loadExtensionFromPath(call.argument<String>("path")!!)
        "getInstalledExtensions" -> true to Bridge.getInstalledExtensions()
        "loadExtensionsFromDir" -> true to Bridge.loadExtensionsFromDir(call.argument<String>("dirPath")!!)
        "setExtensionEnabled" -> {
            Bridge.setExtensionEnabledByID(
                call.argument<String>("id")!!,
                call.argument<Boolean>("enabled")!!
            )
            true to null
        }
        "removeExtension" -> {
            Bridge.removeExtensionByID(call.argument<String>("id")!!)
            true to null
        }
        "searchTracks" -> true to Bridge.searchTracksWithMetadataProvidersJSON(
            call.argument<String>("query")!!,
            (call.argument<Int>("limit") ?: 20).toLong(),
            call.argument<Boolean>("includeExtensions") ?: true
        )
        "downloadByStrategy" -> true to Bridge.downloadByStrategy(call.argument<String>("requestJson")!!)
        "getAllProgress" -> true to Bridge.getAllDownloadProgress()
        "cancelDownload" -> {
            Bridge.cancelDownload(call.argument<String>("itemId")!!)
            true to null
        }
        "setDownloadDirectory" -> {
            Bridge.setDownloadDirectory(call.argument<String>("path")!!)
            true to null
        }
        "allowDownloadDir" -> {
            Bridge.allowDownloadDir(call.argument<String>("path")!!)
            true to null
        }
        "checkDuplicate" -> true to Bridge.checkDuplicate(
            call.argument<String>("outputDir")!!,
            call.argument<String>("isrc")!!
        )
        "getExtensionSettings" -> true to Bridge.getExtensionSettingsJSON(call.argument<String>("id")!!)
        "setExtensionSettings" -> {
            Bridge.setExtensionSettingsJSON(
                call.argument<String>("id")!!,
                call.argument<String>("settingsJson")!!
            )
            true to null
        }
        "getDownloadPriority" -> true to Bridge.getProviderPriorityJSON()
        "setDownloadPriority" -> {
            Bridge.setProviderPriorityJSON(call.argument<String>("priorityJson")!!)
            true to null
        }
        "getMetadataPriority" -> true to Bridge.getMetadataProviderPriorityJSON()
        "setMetadataPriority" -> {
            Bridge.setMetadataProviderPriorityJSON(call.argument<String>("priorityJson")!!)
            true to null
        }
        "startMediaServer" -> {
            val status = Bridge.startMediaServer(
                call.argument<String>("rootDir")!!,
                call.argument<String>("name")!!
            )
            acquireMulticastLock()
            true to status
        }
        "stopMediaServer" -> {
            Bridge.stopMediaServer()
            releaseMulticastLock()
            true to null
        }
        "getMediaServerStatus" -> true to Bridge.getMediaServerStatus()
        else -> false to null
    }

    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("lossless-dlna").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseMulticastLock()
        bridgeExecutor.shutdown()
        super.onDestroy()
    }
}
