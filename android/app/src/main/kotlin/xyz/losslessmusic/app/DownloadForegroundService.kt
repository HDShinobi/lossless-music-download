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

        @Volatile private var isRunning = false
        fun isServiceRunning(): Boolean = isRunning

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
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null
    private var notifTitle = "Downloading..."
    private var notifText = ""
    private var notifProgress = 0L
    private var notifTotal = 0L

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
        isRunning = false
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
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
        releaseWakeLock()
        serviceScope.cancel()
        isRunning = false
        super.onDestroy()
    }

    // Deliberately not overriding onTaskRemoved(): the whole point of this
    // service is that downloads keep running after the user swipes the app
    // away from Recent Apps. The default Service behavior (keep running) is
    // exactly what's wanted here.
}
