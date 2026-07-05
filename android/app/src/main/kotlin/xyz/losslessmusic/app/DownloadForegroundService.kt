package xyz.losslessmusic.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import xyz.losslessmusic.backend.bridge.Bridge
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

    private data class WorkerItemState(
        val itemId: String,
        var status: String = "queued",
        var progress: Double = 0.0,
        var bytesReceived: Long = 0L,
        var bytesTotal: Long = 0L,
        var error: String? = null,
        // Extension the backend reported for a failed download (its result's
        // `service` field) — lets Dart open the right verification challenge.
        var service: String? = null,
        // Winning provider reported by a successful download's result JSON.
        var resolvedService: String? = null,
    )

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null
    private var notifTitle = "Downloading..."
    private var notifText = ""
    private var notifProgress = 0L
    private var notifTotal = 0L
    @Volatile private var currentRunId = ""
    private val workerItems = mutableListOf<WorkerItemState>()
    private val workerItemsLock = Any()
    private var workerJob: Job? = null
    @Volatile private var currentItemId = ""

    override fun onCreate() {
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
        // touching Bridge.* from a process where Dart never initialized
        // anything (extensions, app version, etc.).
        if (intent == null) {
            stopForegroundService()
            return START_NOT_STICKY
        }

        when (intent.action) {
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
        workerJob?.cancel()
        workerJob = null
        val itemId = currentItemId
        if (itemId.isNotEmpty()) {
            try { Bridge.cancelDownload(itemId) } catch (_: Exception) {}
        }
        currentItemId = ""
        isRunning = false
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

        currentRunId = try { JSONObject(settingsJson).optString("run_id", "") } catch (_: Exception) { "" }
        synchronized(workerItemsLock) {
            workerItems.clear()
            workerItems.addAll(requests.map { WorkerItemState(itemId = it.itemId) })
        }
        startForegroundService()
        writeSnapshot(isRunning = true)

        workerJob?.cancel()
        workerJob = serviceScope.launch { runWorker(requests) }
    }

    private fun updateItem(itemId: String, update: (WorkerItemState) -> Unit) {
        synchronized(workerItemsLock) {
            workerItems.firstOrNull { it.itemId == itemId }?.let(update)
        }
    }

    private suspend fun runWorker(requests: List<WorkerRequest>) {
        for (request in requests) {
            if (!serviceScope.isActive) break
            currentItemId = request.itemId
            updateItem(request.itemId) { it.status = "downloading" }
            notifTitle = if (requests.size > 1) "Downloading ${requests.size} tracks" else request.trackName
            notifText = request.artistName
            writeSnapshot(isRunning = true)

            // Preflight duplicate check (mirrors the Dart-only path).
            if (isDuplicate(request.requestJson)) {
                updateItem(request.itemId) { it.status = "done"; it.progress = 1.0 }
                writeSnapshot(isRunning = true)
                continue
            }

            val progressJob = serviceScope.launch { pollProgress(request.itemId) }
            val resultJson = try {
                Bridge.downloadByStrategy(request.requestJson)
            } catch (e: Exception) {
                progressJob.cancel()
                updateItem(request.itemId) { it.status = "failed"; it.error = e.message ?: "download failed" }
                writeSnapshot(isRunning = true)
                continue
            }
            progressJob.cancel()

            val result = try { JSONObject(resultJson) } catch (_: Exception) { JSONObject() }
            val failed = !result.optBoolean("success", false)
            if (failed) {
                val error = result.optString("error", "unknown")
                val service = result.optString("service", "").ifEmpty { null }
                updateItem(request.itemId) {
                    it.status = "failed"
                    it.error = error
                    it.service = service
                }
                writeSnapshot(isRunning = true)
                continue
            }

            updateItem(request.itemId) { it.status = "finalizing" }
            val winning = result.optString("service", "").ifEmpty { null }
            updateItem(request.itemId) { it.resolvedService = winning }
            writeSnapshot(isRunning = true)
            val filePath = result.optString("file_path", "")
            LrcSidecarWriter.maybeWrite(filePath, request.requestJson)
            if (filePath.isNotEmpty() && NonFlacMetadataEmbedder.isEmbeddable(filePath)) {
                try {
                    NonFlacMetadataEmbedder.embed(applicationContext, filePath, request.requestJson)
                } catch (e: Exception) {
                    android.util.Log.w("DownloadForegroundService", "Non-FLAC metadata embed failed: ${e.message}")
                }
            }
            // FLAC needs no extra step -- go_backend already tagged it natively.

            updateItem(request.itemId) { it.status = "done"; it.progress = 1.0 }
            writeSnapshot(isRunning = true)
        }
        writeSnapshot(isRunning = false)
        stopForegroundService()
    }

    private fun isDuplicate(requestJson: String): Boolean {
        return try {
            val req = JSONObject(requestJson)
            val isrc = req.optString("isrc", "")
            val outputDir = req.optString("output_dir", "")
            if (isrc.isEmpty() || outputDir.isEmpty()) return false
            JSONObject(Bridge.checkDuplicate(outputDir, isrc)).optBoolean("exists", false)
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun pollProgress(itemId: String) {
        while (serviceScope.isActive) {
            try {
                val root = JSONObject(Bridge.getAllDownloadProgress())
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
        val snapshot = JSONObject()
            .put("run_id", currentRunId)
            .put("is_running", isRunning)
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
                        .apply { item.service?.let { put("service", it) } }
                        .apply { item.resolvedService?.let { put("resolved_service", it) } }
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
            .setContentText(notifText)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (notifTotal > 0) {
            builder.setProgress(100, (notifProgress * 100 / notifTotal).toInt(), false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    override fun onDestroy() {
        if (currentItemId.isNotEmpty()) {
            try { Bridge.cancelDownload(currentItemId) } catch (_: Exception) {}
        }
        releaseWakeLock()
        serviceScope.cancel()
        isRunning = false
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ dataSync foreground services get a 6-hour cumulative
        // runtime limit per 24h. Stop cleanly; unfinished items stay
        // "downloading" in the last snapshot and are re-queued the next time
        // the app opens and re-triggers the queue.
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
 * same `Bridge.getLyricsLRC(...)` export `NonFlacMetadataEmbedder.fetchLyrics`
 * uses -- no local file path is passed, since the Go backend's file-path mode
 * only reads lyrics already embedded in the file (nothing is embedded yet at
 * this point in the pipeline) and would return empty, so the sidecar would
 * never write. Runs on BOTH FLAC and non-FLAC downloads (unlike
 * [NonFlacMetadataEmbedder], which only tags lossy formats). Best-effort:
 * failures are logged, never thrown.
 */
private object LrcSidecarWriter {

    fun maybeWrite(filePath: String, requestJson: String) {
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

        try {
            File("$base.lrc").writeText(trimmed, Charsets.UTF_8)
        } catch (e: Exception) {
            android.util.Log.w("LrcSidecarWriter", "sidecar write failed: ${e.message}")
        }
    }

    // Mirrors NonFlacMetadataEmbedder.fetchLyrics verbatim: spotify_id +
    // track_name + artist_name + an empty filePath (forces the online fetch
    // path in go_backend) + duration_ms. No qobuz/tidal id routing exists in
    // that reference call, so none is invented here.
    private fun fetchLyricsOnline(request: JSONObject): String {
        val spotifyId = request.optString("spotify_id", "")
        return Bridge.getLyricsLRC(
            spotifyId,
            request.optString("track_name", ""),
            request.optString("artist_name", ""),
            "",
            request.optLong("duration_ms", 0L),
        )
    }
}
