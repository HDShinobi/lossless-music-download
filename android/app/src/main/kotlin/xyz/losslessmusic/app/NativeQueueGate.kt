package xyz.losslessmusic.app

import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.concurrent.ConcurrentHashMap

/** Admission gate: pausing drains admitted work, without touching engine cancellation leases. */
internal class NativeQueueGate(limit: Int) {
    val concurrency = limit.coerceIn(1, 3)
    private val slots = Semaphore(concurrency)
    private var manualPaused = false
    private var networkPaused = false

    val pauseReason: String?
        @Synchronized get() = if (manualPaused) "paused" else if (networkPaused) "waiting_wifi" else null
    val isPaused: Boolean get() = pauseReason != null

    @Synchronized fun setPaused(paused: Boolean) { manualPaused = paused }
    @Synchronized fun setNetwork(wifiOnly: Boolean, wifi: Boolean, unmetered: Boolean,
        internet: Boolean = true, ethernet: Boolean = false) {
        networkPaused = wifiOnly && !((wifi || ethernet) && internet && unmetered)
    }

    suspend fun <T> runAll(items: List<T>,
        providerKey: (T) -> String = { "default" },
        providerLimit: (T) -> Int = { 3 },
        block: suspend (T) -> Unit,
    ) = coroutineScope {
        val providerSlots = ConcurrentHashMap<String, Semaphore>()
        val pending = items.iterator()
        List(concurrency) {
            launch {
                while (true) {
                    val item = synchronized(pending) {
                        if (pending.hasNext()) pending.next() else null
                    } ?: break
                    val provider = providerSlots.computeIfAbsent(providerKey(item)) {
                        Semaphore(minOf(concurrency, providerLimit(item).coerceIn(1, 3)))
                    }
                    provider.withPermit { withSlot { block(item) } }
                }
            }
        }.joinAll()
    }

    suspend fun <T> withSlot(block: suspend () -> T): T {
        while (true) {
            slots.acquire()
            // The permit plus this check admits an item atomically with pause.
            val admitted = synchronized(this) { !isPaused }
            if (admitted) break
            slots.release()
            delay(100)
        }
        try { return block() } finally { slots.release() }
    }
}

internal data class NativeWorkerItemState(
    val itemId: String,
    var status: String = "queued",
    var progress: Double = 0.0,
    var bytesReceived: Long = 0L,
    var bytesTotal: Long = 0L,
    var error: String? = null,
    // Seconds the backend asked us to wait before retrying a rate-limited
    // (HTTP 429) item, from the download result's `retry_after_seconds`.
    // 0 when absent. Surfaced to Dart so its backoff honors the server's
    // Retry-After instead of the 30s default (which retries too early and
    // gets the IP re-throttled). Mirrors SpotiFLAC's retry_after handling.
    var retryAfterSeconds: Int = 0,
    // Extension the backend reported for a failed download (its result's
    // `service` field) — lets Dart open the right verification challenge.
    var service: String? = null,
    // Winning provider reported by a successful download's result JSON.
    var resolvedService: String? = null,
    var filePath: String? = null,
) {
    fun requeueOnStop() {
        if (status != "downloading" && status != "finalizing") return
        status = "queued"
        progress = 0.0
        bytesReceived = 0L
        bytesTotal = 0L
        error = null
    }
}

