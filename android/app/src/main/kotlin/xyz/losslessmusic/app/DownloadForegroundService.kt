package xyz.losslessmusic.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import xyz.losslessmusic.app.engine.Engines
import java.io.File
import java.io.FileOutputStream

/**
 * Foreground service that keeps downloads running when the app is
 * backgrounded or the user swipes it away from Recent Apps. Execution lives
 * here (not in Dart) so it doesn't depend on a live Flutter engine.
 */
class DownloadForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "download_channel"
        private const val NOTIFICATION_ID = 1001
        private const val WAKELOCK_TAG = "LosslessMusic:DownloadWakeLock"
        private const val WAKELOCK_RENEW_MS = 30 * 60 * 1000L

        private const val ACTION_START = "xyz.losslessmusic.app.action.START"
        private const val ACTION_STOP = "xyz.losslessmusic.app.action.STOP"
        private const val ACTION_UPDATE = "xyz.losslessmusic.app.action.UPDATE"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS = "progress"
        private const val EXTRA_TOTAL = "total"
        private const val SNAPSHOT_FILE = "native_download_worker_snapshot.json"
        private const val ACTION_PAUSE = "xyz.losslessmusic.app.action.PAUSE"
        private const val ACTION_RESUME = "xyz.losslessmusic.app.action.RESUME"
        private const val ACTION_START_QUEUE = "xyz.losslessmusic.app.action.START_QUEUE"
        private const val EXTRA_REQUESTS_JSON = "requests_json"
        private const val EXTRA_SETTINGS_JSON = "settings_json"

        @Volatile private var isRunning = false

        fun start(context: Context) {
            val intent = Intent(context, DownloadForegroundService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, DownloadForegroundService::class.java).setAction(ACTION_STOP)
            )
        }

        fun updateNotification(context: Context, title: String, text: String, progress: Long, total: Long) {
            context.startService(
                Intent(context, DownloadForegroundService::class.java)
                    .setAction(ACTION_UPDATE)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_TEXT, text)
                    .putExtra(EXTRA_PROGRESS, progress)
                    .putExtra(EXTRA_TOTAL, total)
            )
        }

        fun startQueue(context: Context, requestsJson: String, settingsJson: String) {
            val intent = Intent(context, DownloadForegroundService::class.java)
                .setAction(ACTION_START_QUEUE)
                .putExtra(EXTRA_REQUESTS_JSON, requestsJson)
                .putExtra(EXTRA_SETTINGS_JSON, settingsJson)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun setPaused(context: Context, paused: Boolean) {
            context.startService(Intent(context, DownloadForegroundService::class.java)
                .setAction(if (paused) ACTION_PAUSE else ACTION_RESUME))
        }

        fun networkAllowed(context: Context): Boolean {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
            return (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        }

        fun readSnapshot(context: Context): String {
            val file = File(context.filesDir, SNAPSHOT_FILE)
            if (!file.exists()) return ""
            return try { file.readText() } catch (_: Exception) { "" }
        }
    }

    private data class WorkerRequest(
        val itemId: String,
        val trackName: String,
        val artistName: String,
        val requestJson: String,
    )

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null
    private var notifTitle = "Downloading..."
    private var notifText = ""
    private var notifProgress = 0L
    private var notifTotal = 0L
    @Volatile private var currentRunId = ""
    private val workerItems = mutableListOf<NativeWorkerItemState>()
    private val workerItemsLock = Any()
    private var workerJob: Job? = null
    @Volatile private var workerStopped = true
    private var gate = NativeQueueGate(1)
    private var wifiOnly = false
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkFallbackJob: Job? = null
    private var pausedLabel = "Paused"
    private var waitingLabel = "Waiting for Wi-Fi"
    private var pauseLabel = "Pause"
    private var resumeLabel = "Resume"

    override fun onCreate() {
        Engines.init(applicationContext)
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows download progress"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The OS restarting us with no pending work (e.g. after killing the
        // process under memory pressure) -- bail out cleanly rather than
        // touching Engines.current from a process where Dart never initialized
        // anything (extensions, app version, etc.).
        if (intent == null) {
            stopForegroundService()
            return START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_PAUSE, ACTION_RESUME -> {
                if (workerJob?.isActive != true) {
                    // startId-scoped: never tear down a START_QUEUE queued behind us.
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                gate.setPaused(intent.action == ACTION_PAUSE)
                refreshQueueState()
            }
            ACTION_START -> startForegroundService()
            ACTION_STOP -> stopForegroundService()
            ACTION_UPDATE -> {
                notifTitle = intent.getStringExtra(EXTRA_TITLE) ?: notifTitle
                notifText = intent.getStringExtra(EXTRA_TEXT) ?: notifText
                notifProgress = intent.getLongExtra(EXTRA_PROGRESS, notifProgress)
                notifTotal = intent.getLongExtra(EXTRA_TOTAL, notifTotal)
                if (isRunning) {
                    ensureWakeLock()
                    getSystemService(NotificationManager::class.java)
                        .notify(NOTIFICATION_ID, buildNotification())
                }
            }
            ACTION_START_QUEUE -> {
                val requestsJson = intent.getStringExtra(EXTRA_REQUESTS_JSON) ?: "[]"
                val settingsJson = intent.getStringExtra(EXTRA_SETTINGS_JSON) ?: "{}"
                startQueueInternal(requestsJson, settingsJson)
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Synchronized
    private fun ensureWakeLock() {
        val existing = wakeLock
        if (existing?.isHeld == true) {
            existing.acquire(WAKELOCK_RENEW_MS)
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
            setReferenceCounted(false)
            acquire(WAKELOCK_RENEW_MS)
        }
    }

    @Synchronized
    private fun releaseWakeLock() {
        val existing = wakeLock
        wakeLock = null
        if (existing?.isHeld == true) {
            try { existing.release() } catch (_: RuntimeException) {}
        }
    }

    private fun startForegroundService() {
        isRunning = true
        ensureWakeLock()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Synchronized
    private fun stopForegroundService() {
        // Stop processing further queued items, but deliberately do NOT call
        // Engines.current.cancelDownload() here. This runs on natural batch completion
        // (runWorker's tail) as well as on forced stop, and cancelling the engine download for the
        // current item leaves a stale "cancelled" entry in the backend's cancel
        // map that poisons any later re-download of the SAME itemId (e.g. a
        // rate-limit 429 retry, which re-queues the same item) — surfacing as a
        // bogus "download cancelled" failure. Mirrors SpotiFLAC's DownloadService,
        // which cancels the engine download only on an explicit user pause/cancel. Explicit user
        // cancellation still works: it goes through the Dart remove() path, which
        // calls Engines.current.cancelDownload() directly.
        if (!workerStopped) {
            workerStopped = true
            synchronized(workerItemsLock) { workerItems.forEach { it.requeueOnStop() } }
            writeSnapshot(isRunning = false)
        }
        workerJob?.cancel()
        workerJob = null
        isRunning = false
        unregisterNetworkCallback()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun parseRequests(requestsJson: String): List<WorkerRequest> {
        val array = JSONArray(requestsJson)
        val out = ArrayList<WorkerRequest>(array.length())
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val itemId = item.optString("item_id").trim()
            val requestJson = item.optString("request_json").trim()
            if (itemId.isEmpty() || requestJson.isEmpty()) continue
            out.add(
                WorkerRequest(
                    itemId = itemId,
                    trackName = item.optString("track_name"),
                    artistName = item.optString("artist_name"),
                    requestJson = requestJson,
                )
            )
        }
        return out
    }

    private fun startQueueInternal(requestsJson: String, settingsJson: String) {
        val requests = try {
            parseRequests(requestsJson)
        } catch (e: Exception) {
            android.util.Log.w("DownloadForegroundService", "Invalid requests JSON: ${e.message}")
            return
        }
        if (requests.isEmpty()) return

        // A second START_QUEUE must never replace a batch whose blocking engine calls are alive.
        if (workerJob?.isActive == true) return
        val settings = try { JSONObject(settingsJson) } catch (_: Exception) { JSONObject() }
        currentRunId = settings.optString("run_id", "")
        gate = NativeQueueGate(settings.optInt("concurrent_downloads", 1))
        gate.setPaused(settings.optBoolean("is_paused", false))
        wifiOnly = settings.optBoolean("wifi_only", false)
        pausedLabel = settings.optString("paused_label", "Paused")
        waitingLabel = settings.optString("waiting_wifi_label", "Waiting for Wi-Fi")
        pauseLabel = settings.optString("pause_label", "Pause")
        resumeLabel = settings.optString("resume_label", "Resume")
        workerStopped = false
        synchronized(workerItemsLock) {
            workerItems.clear()
            workerItems.addAll(requests.map { NativeWorkerItemState(itemId = it.itemId) })
        }
        registerNetworkCallback()
        startForegroundService()
        writeSnapshot(isRunning = true)

        workerJob?.cancel()
        workerJob = serviceScope.launch { runWorker(requests) }
    }

    private fun updateItem(itemId: String, update: (NativeWorkerItemState) -> Unit) {
        synchronized(workerItemsLock) {
            if (workerStopped) return
            workerItems.firstOrNull { it.itemId == itemId }?.let(update)
        }
    }

    private suspend fun runWorker(requests: List<WorkerRequest>) {
        gate.runAll(requests,
            providerKey = { request ->
                val payload = try { JSONObject(request.requestJson) } catch (_: Exception) { JSONObject() }
                payload.optString("download_provider", "").ifBlank { payload.optString("service", "") }
                    .trim().lowercase().ifBlank { "default" }
            },
            providerLimit = { request ->
                try { JSONObject(request.requestJson).optInt("network_concurrency_limit", 3) }
                catch (_: Exception) { 3 }
            },
        ) { request ->
            try { processItem(request, requests.size) }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) {
                updateItem(request.itemId) { it.status = "failed"; it.error = e.message }
                writeSnapshot(isRunning = true)
            }
        }
        writeSnapshot(isRunning = false)
        stopForegroundService()
    }

    private val outputPostProcessor = OutputPostProcessor()

    private suspend fun processItem(request: WorkerRequest, count: Int) {
        currentCoroutineContext().ensureActive()
        updateItem(request.itemId) { it.status = "downloading" }
        notifTitle = if (count > 1) "Downloading ${count} tracks" else request.trackName
        notifText = request.artistName
        writeSnapshot(isRunning = true)

        // Preflight duplicate check (mirrors the Dart-only path).
        val duplicate = isDuplicate(request.requestJson)
        currentCoroutineContext().ensureActive()
        if (duplicate) {
            updateItem(request.itemId) { it.status = "done"; it.progress = 1.0 }
            writeSnapshot(isRunning = true)
            return
        }

        val progressJob = CoroutineScope(currentCoroutineContext()).launch { pollProgress(request.itemId) }
        val resultJson = try {
            Engines.current.downloadByStrategy(request.requestJson)
        } catch (e: Exception) {
            currentCoroutineContext().ensureActive()
            progressJob.cancel()
            updateItem(request.itemId) { it.status = "failed"; it.error = e.message ?: "download failed" }
            writeSnapshot(isRunning = true)
            return
        }
        progressJob.cancel()
        currentCoroutineContext().ensureActive()

        val result = try { JSONObject(resultJson) } catch (_: Exception) { JSONObject() }
        val failed = !result.optBoolean("success", false)
        if (failed) {
            val error = result.optString("error", "unknown")
            val service = result.optString("service", "").ifEmpty { null }
            val retryAfter = result.optInt("retry_after_seconds", 0)
            updateItem(request.itemId) {
                it.status = "failed"
                it.error = error
                it.retryAfterSeconds = retryAfter
                it.service = service
            }
            writeSnapshot(isRunning = true)
            return
        }

        updateItem(request.itemId) { it.status = "finalizing" }
        val winning = result.optString("service", "").ifEmpty { null }
        updateItem(request.itemId) { it.resolvedService = winning }
        writeSnapshot(isRunning = true)
        // Amazon's lossless tier delivers an *encrypted* MP4 plus the key in
        // the result; the engine only forwards it, so decrypt (and unwrap the
        // FLAC out of the MP4) here, before the sidecar and tagging steps see
        // the path. Without this the file is ciphertext that merely labels
        // itself as hi-res FLAC.
        val filePath = outputPostProcessor.run(result) {
            val finalizedPath = try {
                Mp4FlacUnwrapper.finalize(result.toString(), request.requestJson)
            } catch (e: Exception) {
                android.util.Log.w("DownloadForegroundService", "MP4 finalize failed: ${e.message}")
                result.optString("file_path", "")
            }
            LrcSidecarWriter.maybeWrite(finalizedPath, request.requestJson)
            if (finalizedPath.isNotEmpty() && NonFlacMetadataEmbedder.isEmbeddable(finalizedPath)) {
                try {
                    NonFlacMetadataEmbedder.embed(applicationContext, finalizedPath, request.requestJson)
                } catch (e: Exception) {
                    android.util.Log.w("DownloadForegroundService", "Non-FLAC metadata embed failed: ${e.message}")
                }
            }
            finalizedPath
        }
        // FLAC needs no extra step -- the engine already tagged it natively.

        currentCoroutineContext().ensureActive()
        updateItem(request.itemId) { it.status = "done"; it.progress = 1.0; it.filePath = filePath }
        writeSnapshot(isRunning = true)
    }

    private fun refreshQueueState() {
        if (workerStopped) return
        writeSnapshot(isRunning = workerJob?.isActive == true)
        if (isRunning) getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    private fun refreshNetwork() {
        val allowed = networkAllowed(this)
        gate.setNetwork(wifiOnly, allowed, allowed)
        refreshQueueState()
    }

    private fun registerNetworkCallback() {
        unregisterNetworkCallback()
        val allowed = networkAllowed(this)
        gate.setNetwork(wifiOnly, allowed, allowed)
        if (!wifiOnly) return
        val callback = object : ConnectivityManager.NetworkCallback() {
            private var trackedNetwork: Network? = null
            override fun onAvailable(network: Network) { trackedNetwork = network }
            override fun onLost(network: Network) {
                if (network != trackedNetwork) return
                trackedNetwork = null
                gate.setNetwork(wifiOnly, wifi = false, unmetered = false)
                refreshQueueState()
            }
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                if (network != trackedNetwork) return
                gate.setNetwork(wifiOnly,
                    wifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                    ethernet = caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    internet = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                    unmetered = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
                refreshQueueState()
            }
        }
        try {
            getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (e: Exception) {
            android.util.Log.w("DownloadForegroundService", "Network callback unavailable: ${e.message}")
        }
        // Also recover from missed callbacks while waiting for an allowed network.
        networkFallbackJob = serviceScope.launch {
            while (isActive) {
                delay(5000)
                if (gate.pauseReason == "waiting_wifi") refreshNetwork()
            }
        }
    }

    private fun unregisterNetworkCallback() {
        networkFallbackJob?.cancel()
        networkFallbackJob = null
        networkCallback?.let {
            runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) }
        }
        networkCallback = null
    }

    private fun isDuplicate(requestJson: String): Boolean {
        return try {
            val req = JSONObject(requestJson)
            if (req.optBoolean("bypass_duplicate_check", false)) return false
            val isrc = req.optString("isrc", "")
            val outputDir = req.optString("output_dir", "")
            if (isrc.isEmpty() || outputDir.isEmpty()) return false
            JSONObject(Engines.current.checkDuplicate(outputDir, isrc)).optBoolean("exists", false)
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun pollProgress(itemId: String) {
        while (currentCoroutineContext().isActive) {
            try {
                val root = JSONObject(Engines.current.getAllDownloadProgress())
                currentCoroutineContext().ensureActive()
                val items = root.optJSONObject("items")
                val progress = items?.optJSONObject(itemId)
                if (progress != null) {
                    val bytesReceived = progress.optLong("bytes_received", 0L)
                    val bytesTotal = progress.optLong("bytes_total", 0L)
                    val progressValue = if (bytesTotal > 0) bytesReceived.toDouble() / bytesTotal else 0.0
                    updateItem(itemId) {
                        it.progress = progressValue
                        it.bytesReceived = bytesReceived
                        it.bytesTotal = bytesTotal
                    }
                    if (bytesTotal > 0) {
                        // Update fields + renotify directly -- this already runs
                        // as an instance method inside the service, so there's
                        // no need to round-trip through a self-addressed Intent
                        // the way the companion updateNotification() helper does
                        // for external callers.
                        notifProgress = bytesReceived
                        notifTotal = bytesTotal
                        if (isRunning) {
                            ensureWakeLock()
                            getSystemService(NotificationManager::class.java)
                                .notify(NOTIFICATION_ID, buildNotification())
                        }
                    }
                    writeSnapshot(isRunning = true)
                }
            } catch (_: Exception) {
            }
            delay(1000)
        }
    }

    @Synchronized
    private fun writeSnapshot(isRunning: Boolean) {
        // A blocking engine call may return after stop cancelled its coroutine.
        if (isRunning && workerStopped) return
        val pauseReason = gate.pauseReason
        val snapshot = JSONObject()
            .put("run_id", currentRunId)
            .put("is_running", isRunning)
            .put("is_paused", pauseReason != null)
            .put("pause_reason", pauseReason ?: "")
        val items = JSONArray()
        synchronized(workerItemsLock) {
            for (item in workerItems) {
                items.put(
                    JSONObject()
                        .put("item_id", item.itemId)
                        .put("status", item.status)
                        .put("progress", item.progress)
                        .put("bytes_received", item.bytesReceived)
                        .put("bytes_total", item.bytesTotal)
                        .apply { item.error?.let { put("error", it) } }
                        .apply { if (item.retryAfterSeconds > 0) put("retry_after_seconds", item.retryAfterSeconds) }
                        .apply { item.service?.let { put("service", it) } }
                        .apply { item.resolvedService?.let { put("resolved_service", it) } }
                        .apply { item.filePath?.let { put("file_path", it) } }
                )
            }
        }
        snapshot.put("items", items)

        try {
            val tempFile = File(filesDir, "$SNAPSHOT_FILE.tmp")
            FileOutputStream(tempFile).use { it.write(snapshot.toString().toByteArray(Charsets.UTF_8)) }
            if (!tempFile.renameTo(File(filesDir, SNAPSHOT_FILE))) {
                android.util.Log.w("DownloadForegroundService", "Failed to rename snapshot temp file")
            }
        } catch (e: Exception) {
            android.util.Log.w("DownloadForegroundService", "Failed to write snapshot: ${e.message}")
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(notifTitle)
            .setContentText(when (gate.pauseReason) { "paused" -> pausedLabel; "waiting_wifi" -> waitingLabel; else -> notifText })
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (currentRunId.isNotEmpty()) {
            val manualPaused = gate.pauseReason == "paused"
            val action = Intent(this, DownloadForegroundService::class.java)
                .setAction(if (manualPaused) ACTION_RESUME else ACTION_PAUSE)
            builder.addAction(0, if (manualPaused) resumeLabel else pauseLabel,
                PendingIntent.getService(this, 1, action,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        if (notifTotal > 0) {
            builder.setProgress(100, (notifProgress * 100 / notifTotal).toInt(), false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    override fun onDestroy() {
        // Never cancel engine downloads for active items here (see stopForegroundService):
        // a stale cancel entry would poison a later re-download of the same
        // itemId. Cancelling the coroutine scope stops further processing; any
        // in-flight native download simply runs to completion on its own thread.
        stopForegroundService()
        serviceScope.cancel()
        isRunning = false
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ dataSync foreground services get a 6-hour cumulative
        // runtime limit per 24h. Publish the stopped run with unfinished items
        // queued so Dart can release its poll and resume on the next admission.
        android.util.Log.w("DownloadForegroundService", "Foreground service timeout reached; stopping.")
        stopForegroundService()
    }

    // Deliberately not overriding onTaskRemoved(): the whole point of this
    // service is that downloads keep running after the user swipes the app
    // away from Recent Apps. The default Service behavior (keep running) is
    // exactly what's wanted here.
}

/**
 * Writes a `.lrc` sidecar beside a downloaded audio file when the request
 * opted in via `write_lrc_sidecar`. Lyrics are fetched ONLINE through the
 * same `Engines.current.getLyricsLRC(...)` method `NonFlacMetadataEmbedder.fetchLyrics`
 * uses -- no local file path is passed, since the engine's file-path mode
 * only reads lyrics already embedded in the file (nothing is embedded yet at
 * this point in the pipeline) and would return empty, so the sidecar would
 * never write. Runs on BOTH FLAC and non-FLAC downloads (unlike
 * [NonFlacMetadataEmbedder], which only tags lossy formats). Best-effort:
 * failures are logged, never thrown.
 */
private object LrcSidecarWriter {

    fun maybeWrite(filePath: String, requestJson: String) {
        // Entire body is guarded by one outer try/catch: this writer is
        // best-effort and must NEVER throw into the caller's per-item
        // coroutine, since an uncaught exception here would abort the whole
        // remaining download batch. Even innocuous-looking calls like
        // File.exists() can throw SecurityException on rare storage edge
        // cases, so nothing here is left unguarded.
        try {
            val request = try { JSONObject(requestJson) } catch (_: Exception) { return }
            if (!request.optBoolean("write_lrc_sidecar", false)) return
            if (filePath.isEmpty() || filePath.startsWith("content://")) return
            if (!File(filePath).exists()) return

            val lrc = try { fetchLyricsOnline(request) } catch (_: Exception) { return }
            val trimmed = lrc.trim()
            if (trimmed.isEmpty() || trimmed == "[instrumental:true]") return

            // Strip only a real extension: the last '.' must come after the last
            // path separator, otherwise a dotted directory name would get
            // truncated instead of the file's own extension.
            val slash = filePath.lastIndexOf('/')
            val dot = filePath.lastIndexOf('.')
            val base = if (dot > slash) filePath.substring(0, dot) else filePath

            File("$base.lrc").writeText(trimmed, Charsets.UTF_8)
        } catch (e: Exception) {
            android.util.Log.w("LrcSidecarWriter", "sidecar skipped: ${e.message}")
        }
    }

    // Mirrors NonFlacMetadataEmbedder.fetchLyrics verbatim: spotify_id +
    // track_name + artist_name + an empty filePath (forces the online fetch
    // path in the engine) + duration_ms. No qobuz/tidal id routing exists in
    // that reference call, so none is invented here.
    private fun fetchLyricsOnline(request: JSONObject): String {
        val spotifyId = request.optString("spotify_id", "")
        return Engines.current.getLyricsLRC(
            spotifyId,
            request.optString("track_name", ""),
            request.optString("artist_name", ""),
            "",
            request.optLong("duration_ms", 0L),
        )
    }
}
