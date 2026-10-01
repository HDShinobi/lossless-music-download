package xyz.losslessmusic.app

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Bundle
import java.io.File
import java.net.Inet4Address
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import org.json.JSONObject
import xyz.losslessmusic.app.engine.Engines
import xyz.losslessmusic.app.engine.RustEngine
import xyz.losslessmusic.app.engine.SessionGrantFailure
import xyz.losslessmusic.app.dlna.EngineMetadataProvider
import xyz.losslessmusic.app.dlna.MediaServerController
import xyz.losslessmusic.app.dlna.RealDlnaRuntime

class MainActivity : FlutterActivity() {
    companion object {
        @Volatile private var dlnaController: MediaServerController? = null
        private var dlnaMulticastLock: WifiManager.MulticastLock? = null
        private var dlnaNetworkCallback: ConnectivityManager.NetworkCallback? = null
        private val dlnaNetworkExecutor = Executors.newSingleThreadExecutor()

        private fun rustDlna(context: Context): MediaServerController = synchronized(this) {
            dlnaController ?: MediaServerController(
                { root, name, ip ->
                    val rust = Engines.current as RustEngine
                    RealDlnaRuntime(root, name, ip, EngineMetadataProvider(
                        rust::readTrackMetadata, rust::extractCoverToFile,
                        File(context.applicationContext.cacheDir, "dlna-art"),
                        thumbnail = DlnaThumbnailer::write,
                    ))
                },
                {
                    val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    if (dlnaMulticastLock == null) {
                        dlnaMulticastLock = wifi.createMulticastLock("lossless-dlna").apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                    }
                },
                {
                    dlnaMulticastLock?.let { if (it.isHeld) it.release() }
                    dlnaMulticastLock = null
                },
            ).also { dlnaController = it }
        }

        private fun lanIpv4(context: Context, requireLanTransport: Boolean = false): String? {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE)
                as? ConnectivityManager ?: return null
            val networks = cm.allNetworks.toMutableList()
            cm.activeNetwork?.let { active ->
                if (!networks.contains(active)) networks.add(active)
            }
            val ranked = networks.sortedByDescending { n ->
                val caps = cm.getNetworkCapabilities(n)
                if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) 1 else 0
            }
            for (n in ranked) {
                val caps = cm.getNetworkCapabilities(n)
                if (requireLanTransport && caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true &&
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) != true) continue
                val lp = cm.getLinkProperties(n) ?: continue
                for (la in lp.linkAddresses) {
                    val addr = la.address
                    if (addr is Inet4Address && !addr.isLoopbackAddress && addr.isSiteLocalAddress) {
                        return addr.hostAddress
                    }
                }
            }
            return null
        }
    }

    private val channel = "xyz.losslessmusic/native"

    // Bridge calls do blocking I/O (network search/download, file probing, server
    // start). Running them on the platform main thread blocks the UI and causes
    // ANRs, so they run on this pool and reply on the main thread. A pool (not a
    // single thread) lets progress polling run while a long download is in flight.
    private val bridgeExecutor = Executors.newFixedThreadPool(4)
    private val initExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Set once configureFlutterEngine runs; used by handleSessionGrantIntent to
    // notify Dart. A cold start's deep link can arrive before this is set, so
    // events raised before then are queued in pendingSessionGrantEvents.
    private var backendChannel: MethodChannel? = null
    private val pendingSessionGrantEvents = mutableListOf<Map<String, Any>>()

    // Flutter's default deep-link handling would otherwise try to route
    // spotiflac:// intents through go_router (as a path) before
    // handleSessionGrantIntent gets a chance to consume them, producing a
    // "no routes for location" error screen. We handle these intents
    // ourselves, so tell Flutter not to.
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        Engines.init(applicationContext)
        super.onCreate(savedInstanceState)
        handleSessionGrantIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSessionGrantIntent(intent)
    }

    /**
     * Delivers a signed-session auth grant (from the spotiflac://session-grant
     * browser redirect) to the extension runtime and completes the exchange.
     * See rust_backend/crates/extensions/src/signed_session/exchange.rs for the flow this closes.
     */
    private fun handleSessionGrantIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (!uri.scheme.equals("spotiflac", ignoreCase = true) ||
            !uri.host.equals("session-grant", ignoreCase = true)
        ) {
            return
        }
        val grant = (uri.getQueryParameter("grant") ?: uri.getQueryParameter("code"))
            ?.trim().orEmpty()
        // `state` is a one-time random callback nonce, NOT the extension ID.
        // completeSessionGrant resolves it to the extension that raised the
        // challenge before storing the grant and completing the exchange. See
        // upstream AppDelegate.swift / MainActivity.kt for the reference flow.
        val callbackState = uri.getQueryParameter("state")?.trim().orEmpty()
        if (grant.isEmpty() || callbackState.isEmpty()) {
            android.util.Log.w("MainActivity", "session-grant redirect missing grant/state")
            return
        }
        intent.data = null
        bridgeExecutor.execute {
            try {
                val extensionId = Engines.current.completeSessionGrant(callbackState, grant)
                mainHandler.post { notifySessionGrantCompleted(extensionId, true) }
            } catch (e: SessionGrantFailure) {
                android.util.Log.w("MainActivity", "session-grant exchange failed: ${e.message}")
                val id = e.extensionId
                if (!id.isNullOrEmpty()) mainHandler.post { notifySessionGrantCompleted(id, false) }
            } catch (e: Exception) {
                android.util.Log.w("MainActivity", "session-grant exchange failed: ${e.message}")
            }
        }
    }

    private fun notifySessionGrantCompleted(extensionId: String, success: Boolean) {
        val payload = mapOf("extension_id" to extensionId, "success" to success)
        val ch = backendChannel
        if (ch == null) {
            pendingSessionGrantEvents.add(payload)
            return
        }
        ch.invokeMethod("extensionSessionGrantCompleted", payload)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Engines.init(applicationContext)
        super.configureFlutterEngine(flutterEngine)
        // Preserve the channel call; RustEngine intentionally ignores the app
        // version and uses EngineVersion.SPOTIFLAC_ENGINE_VERSION for engine HTTP.
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        } catch (_: Exception) { "" }
        Engines.current.setAppVersion(versionName)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        methodChannel.setMethodCallHandler { call, result ->
                val executor = when (call.method) {
                    "setExtensionStorageMasterKey", "initExtensionSystem" -> initExecutor
                    else -> bridgeExecutor
                }
                executor.execute {
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
        backendChannel = methodChannel
        if (pendingSessionGrantEvents.isNotEmpty()) {
            val events = pendingSessionGrantEvents.toList()
            pendingSessionGrantEvents.clear()
            for (event in events) {
                methodChannel.invokeMethod("extensionSessionGrantCompleted", event)
            }
        }

        // Real-time download progress stream (~300 ms push interval).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xyz.losslessmusic/progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                @Volatile private var active = false

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    active = true
                    bridgeExecutor.execute {
                        while (active) {
                            try {
                                val json = Engines.current.getAllDownloadProgress()
                                mainHandler.post { if (active) events.success(json) }
                            } catch (_: Exception) {}
                            Thread.sleep(300)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    active = false
                }
            })
    }

    // Runs on a background thread. Returns (handled, value); the caller posts the
    // result on the main thread.
    private fun dispatch(call: MethodCall): Pair<Boolean, Any?> = when (call.method) {
        "ping" -> true to "pong"
        "getAudioQuality" -> true to Engines.current.getAudioQuality(call.argument<String>("path")!!)
        "setExtensionStorageMasterKey" -> {
            // v4.9.5 gates InitExtensionSystem on this key. Must run before
            // "initExtensionSystem" or extension dirs stay unconfigured and
            // every install/upgrade fails with "extension directory is not
            // configured". Key is a base64 32-byte value held in Keystore.
            val key = call.argument<String>("masterKey")!!
            Engines.current.setExtensionStorageMasterKey(key)
            true to null
        }
        "initExtensionSystem" -> {
            val extDir = call.argument<String>("extDir")!!
            val dataDir = call.argument<String>("dataDir")!!
            Engines.current.initExtensionSystem(extDir, dataDir)
            true to null
        }
        "loadExtensionFromPath" -> true to Engines.current.loadExtensionFromPath(call.argument<String>("path")!!)
        "getInstalledExtensions" -> true to Engines.current.getInstalledExtensions()
        "loadExtensionsFromDir" -> {
            val loaded = Engines.current.loadExtensionsFromDir(call.argument<String>("dirPath")!!)
            true to loaded
        }
        "setExtensionEnabled" -> {
            Engines.current.setExtensionEnabled(
                call.argument<String>("id")!!,
                call.argument<Boolean>("enabled")!!
            )
            true to null
        }
        "removeExtension" -> {
            Engines.current.removeExtension(call.argument<String>("id")!!)
            true to null
        }
        "searchTracks" -> true to Engines.current.searchTracks(
            call.argument<String>("query")!!,
            (call.argument<Int>("limit") ?: 20).toLong(),
            call.argument<Boolean>("includeExtensions") ?: true
        )
        "downloadByStrategy" -> true to Engines.current.downloadByStrategy(call.argument<String>("requestJson")!!)
        "getAllProgress" -> true to Engines.current.getAllDownloadProgress()
        "cancelDownload" -> {
            Engines.current.cancelDownload(call.argument<String>("itemId")!!)
            true to null
        }
        "setDownloadDirectory" -> {
            Engines.current.setDownloadDirectory(call.argument<String>("path")!!)
            true to null
        }
        "allowDownloadDir" -> {
            Engines.current.allowDownloadDir(call.argument<String>("path")!!)
            true to null
        }
        "checkDuplicate" -> true to Engines.current.checkDuplicate(
            call.argument<String>("outputDir")!!,
            call.argument<String>("isrc")!!
        )
        "getExtensionSettings" -> true to Engines.current.getExtensionSettings(call.argument<String>("id")!!)
        "setExtensionSettings" -> {
            Engines.current.setExtensionSettings(
                call.argument<String>("id")!!,
                call.argument<String>("settingsJson")!!
            )
            true to null
        }
        "getDownloadPriority" -> true to Engines.current.getDownloadPriority()
        "setDownloadPriority" -> {
            Engines.current.setDownloadPriority(call.argument<String>("priorityJson")!!)
            true to null
        }
        "getMetadataPriority" -> true to Engines.current.getMetadataPriority()
        "setMetadataPriority" -> {
            Engines.current.setMetadataPriority(call.argument<String>("priorityJson")!!)
            true to null
        }
        "getExtensionHomeFeed" -> true to Engines.current.getExtensionHomeFeed(call.argument<String>("extensionId")!!)
        "setDownloadFallbackProviderIds" -> {
            Engines.current.setDownloadFallbackProviderIds(call.argument<String>("idsJson")!!)
            true to null
        }
        "startMediaServer" -> {
            val status = rustDlna(applicationContext).start(
                call.argument<String>("rootDir")!!, call.argument<String>("name")!!,
                lanIpv4(applicationContext, requireLanTransport = true) ?: "")
            val statusJson = JSONObject(status)
            if (statusJson.optString("state") == "FAILED") {
                throw IllegalStateException(statusJson.optString("error").ifEmpty { "DLNA start failed" })
            }
            registerDlnaNetworkCallback()
            true to status
        }
        "stopMediaServer" -> {
            unregisterDlnaNetworkCallback()
            rustDlna(applicationContext).stop()
            true to null
        }
        "getMediaServerStatus" -> true to rustDlna(applicationContext).statusJson()
        "handleUrl" -> true to Engines.current.handleUrl(call.argument<String>("url")!!)
        "findUrlHandler" -> true to Engines.current.findUrlHandler(call.argument<String>("url")!!)
        "getProviderMetadata" -> true to Engines.current.getProviderMetadata(
            call.argument<String>("providerId")!!,
            call.argument<String>("resourceType")!!,
            call.argument<String>("resourceId")!!,
        )
        "setLibraryCoverCacheDir" -> {
            Engines.current.setLibraryCoverCacheDir(call.argument<String>("cacheDir")!!)
            true to null
        }
        "scanLibraryFolder" -> true to Engines.current.scanLibraryFolder(
            call.argument<String>("folderPath")!!
        )
        "getLyricsLRC" -> true to Engines.current.getLyricsLRC(
            call.argument<String>("spotifyId") ?: "",
            call.argument<String>("trackName") ?: "",
            call.argument<String>("artistName") ?: "",
            call.argument<String>("filePath") ?: "",
            (call.argument<Number>("durationMs") ?: 0).toLong(),
        )
        "editFileMetadata" -> true to Engines.current.editFileMetadata(
            call.argument<String>("filePath")!!,
            call.argument<String>("metadataJson")!!,
        )
        "reEnrichFile" -> true to Engines.current.reEnrichFile(call.argument<String>("requestJson")!!)
        "customSearchWithExtension" -> true to Engines.current.customSearchWithExtension(
            call.argument<String>("extensionId")!!,
            call.argument<String>("query")!!,
            call.argument<String>("optionsJson") ?: "",
        )
        "getExtensionPendingAuth" -> true to Engines.current.getExtensionPendingAuth(
            call.argument<String>("extensionId")!!
        )
        "startNativeDownloadWorker" -> {
            DownloadForegroundService.startQueue(
                applicationContext,
                call.argument<String>("requestsJson")!!,
                call.argument<String>("settingsJson") ?: "{}",
            )
            true to null
        }
        "getNativeDownloadWorkerSnapshot" -> true to DownloadForegroundService.readSnapshot(applicationContext)
        "stopNativeDownloadWorker" -> {
            DownloadForegroundService.stop(applicationContext)
            true to null
        }
        else -> false to null
    }

    private fun registerDlnaNetworkCallback() = synchronized(MainActivity) {
        if (dlnaNetworkCallback != null) return@synchronized
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val app = applicationContext
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLost(network: Network) {
                dlnaNetworkExecutor.execute { dlnaController?.onNetworkChanged(lanIpv4(app, requireLanTransport = true)) }
            }
            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                dlnaNetworkExecutor.execute { dlnaController?.onNetworkChanged(lanIpv4(app, requireLanTransport = true)) }
            }
        }
        cm.registerNetworkCallback(
            NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
                .build(), callback)
        dlnaNetworkCallback = callback
    }

    private fun unregisterDlnaNetworkCallback() = synchronized(MainActivity) {
        val callback = dlnaNetworkCallback ?: return@synchronized
        dlnaNetworkCallback = null
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.unregisterNetworkCallback(callback)
    }

    override fun onDestroy() {
        bridgeExecutor.shutdown()
        initExecutor.shutdown()
        super.onDestroy()
    }
}
