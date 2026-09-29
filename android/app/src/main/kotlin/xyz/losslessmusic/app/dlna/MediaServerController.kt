package xyz.losslessmusic.app.dlna

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import org.json.JSONObject

sealed class ServerState(val name: String) {
    object Stopped : ServerState("STOPPED")
    object Starting : ServerState("STARTING")
    object Running : ServerState("RUNNING")
    object Stopping : ServerState("STOPPING")
    data class Failed(val reason: String) : ServerState("FAILED")
}

interface DlnaRuntime {
    fun start(): String
    fun stop()
    var onFailure: ((String) -> Unit)?
}

class RealDlnaRuntime(rootDir: String, name: String, private val lanIp: String, meta: MetadataProvider?) : DlnaRuntime {
    private val http = MediaServer(rootDir, name, lanIp, meta)
    private var ssdp: SsdpResponder? = null
    override var onFailure: ((String) -> Unit)? = null

    override fun start(): String {
        http.onUnexpectedStop = { onFailure?.invoke(it) }
        val url = http.start()
        try {
            val responder = SsdpResponder(lanIp, "$url/description.xml", http.udn)
            ssdp = responder
            responder.onFailure = { onFailure?.invoke(it) }
            responder.start()
            return url
        } catch (error: Throwable) {
            try { ssdp?.stop() } catch (cleanup: Throwable) { error.addSuppressed(cleanup) }
            ssdp = null
            try { http.stop() } catch (cleanup: Throwable) { error.addSuppressed(cleanup) }
            throw error
        }
    }

    override fun stop() {
        val responder = ssdp
        ssdp = null
        try { responder?.stop() } finally { http.stop() }
    }
}

class MediaServerController(
    private val runtimeFactory: (rootDir: String, name: String, lanIp: String) -> DlnaRuntime,
    private val acquireLock: () -> Unit,
    private val releaseLock: () -> Unit,
) {
    private val lock = ReentrantLock()
    private val changed = lock.newCondition()
    private var current: ServerState = ServerState.Stopped
    private var runtime: DlnaRuntime? = null
    private var startingRuntime: DlnaRuntime? = null
    private var heldLock = false
    private var boundIp = ""
    private var url = ""
    private var serverName = ""
    private var pendingFailure: String? = null
    private var cancelStart = false

    val state: ServerState get() = lock.withLock { current }

    fun start(rootDir: String, name: String, lanIp: String): String {
        val restart = lock.withLock {
            while (current == ServerState.Stopping) changed.await()
            current == ServerState.Running && lanIp.isNotBlank() && lanIp != boundIp
        }
        if (restart) {
            shutDown("network_changed")
            return start(rootDir, name, lanIp)
        }
        lock.withLock {
            while (current == ServerState.Stopping) changed.await()
            if (current == ServerState.Running || current == ServerState.Starting) return statusJsonLocked()
            serverName = name
            url = ""
            if (lanIp.isBlank()) {
                current = ServerState.Failed("no_lan_ip")
                return statusJsonLocked()
            }
            current = ServerState.Starting
            boundIp = lanIp
            pendingFailure = null
            cancelStart = false
            startingRuntime = null
        }
        var candidate: DlnaRuntime? = null
        var lockAttempted = false
        var failure: String? = null
        var startedUrl = ""
        try {
            lockAttempted = true
            acquireLock()
            candidate = runtimeFactory(rootDir, name, lanIp)
            val active = candidate
            lock.withLock { startingRuntime = active }
            active.onFailure = { reason -> failRuntime(active, reason) }
            startedUrl = active.start()
        } catch (error: Throwable) {
            failure = error.message ?: error.javaClass.simpleName
        }
        lock.withLock {
            failure = failure ?: pendingFailure
            if (cancelStart && failure == null) failure = "start_cancelled"
            if (failure == null) {
                runtime = candidate
                startingRuntime = null
                heldLock = lockAttempted
                url = startedUrl
                current = ServerState.Running
                changed.signalAll()
                return statusJsonLocked()
            }
            current = ServerState.Stopping
        }
        try {
            candidate?.onFailure = null
            candidate?.stop()
        } catch (cleanup: Throwable) {
            if (failure == null || failure == "start_cancelled") failure = cleanup.message ?: cleanup.javaClass.simpleName
        } finally {
            try {
                if (lockAttempted) releaseLock()
            } catch (cleanup: Throwable) {
                failure = cleanup.message ?: cleanup.javaClass.simpleName
            } finally {
                lock.withLock {
                    runtime = null
                    startingRuntime = null
                    heldLock = false
                    url = ""
                    boundIp = ""
                    current = if (cancelStart && pendingFailure == null && failure == "start_cancelled") ServerState.Stopped else ServerState.Failed(failure!!)
                    changed.signalAll()
                }
            }
        }
        return statusJson()
    }

    fun stop() = shutDown(null)

    fun onNetworkChanged(currentLanIp: String?) {
        val changedIp = lock.withLock {
            (current == ServerState.Starting || current == ServerState.Running) && currentLanIp != boundIp
        }
        if (changedIp) shutDown("network_changed")
    }

    fun statusJson(): String = lock.withLock { statusJsonLocked() }

    private fun failRuntime(source: DlnaRuntime, reason: String) {
        lock.withLock {
            if (current == ServerState.Starting) {
                if (startingRuntime !== source) return
                if (pendingFailure == null) pendingFailure = reason
                return
            }
            if (runtime !== source || current != ServerState.Running) return
        }
        shutDown(reason, expectedRuntime = source)
    }

    private fun shutDown(reason: String?, expectedRuntime: DlnaRuntime? = null) {
        val active: DlnaRuntime?
        val release: Boolean
        lock.withLock {
            while (current == ServerState.Stopping) changed.await()
            if (expectedRuntime != null && runtime !== expectedRuntime) return
            if (current == ServerState.Starting) {
                cancelStart = true
                if (reason != null) pendingFailure = reason
                while (current == ServerState.Starting || current == ServerState.Stopping) changed.await()
            }
            if (current != ServerState.Running) {
                if (reason == null && current is ServerState.Failed) current = ServerState.Stopped
                return
            }
            current = ServerState.Stopping
            active = runtime
            runtime = null
            release = heldLock
            heldLock = false
        }
        var failure = reason
        try {
            active?.onFailure = null
            active?.stop()
        } catch (error: Throwable) {
            if (failure == null) failure = error.message ?: error.javaClass.simpleName
        } finally {
            try {
                if (release) releaseLock()
            } catch (error: Throwable) {
                if (failure == null) failure = error.message ?: error.javaClass.simpleName
            } finally {
                lock.withLock {
                    url = ""
                    boundIp = ""
                    current = if (failure == null) ServerState.Stopped else ServerState.Failed(failure!!)
                    changed.signalAll()
                }
            }
        }
    }

    private fun statusJsonLocked(): String = JSONObject()
        .put("running", current == ServerState.Running)
        .put("url", url)
        .put("name", serverName)
        .put("state", current.name)
        .put("error", (current as? ServerState.Failed)?.reason ?: "")
        .toString()
}
