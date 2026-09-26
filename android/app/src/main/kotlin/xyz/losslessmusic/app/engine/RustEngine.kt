package xyz.losslessmusic.app.engine

import com.zarz.spotiflac.requireSuccessfulExtensionAction
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * NativeEngine on the vendored Rust engine (spec §3.1). Keeps the Go-era contract: throws where Go
 * throws, returns defaults where Go cannot fail (R-P1). Pure JVM (no android.*) so it is unit-tested
 * with FakeRustCore.
 */
class RustEngine(
    private val factory: RustCoreFactory,
    private val filesDir: File,
    private val readyTimeoutMs: Long = DEFAULT_READY_TIMEOUT_MS,
    private val log: (String) -> Unit = {},
) : NativeEngine {
    companion object {
        const val DEFAULT_READY_TIMEOUT_MS = 15_000L
        const val NOT_READY = "engine_not_ready"
        const val MISSING_KEY = "extension storage master key is not configured"
    }

    enum class State { UNINITIALIZED, INITIALIZING, READY, FAILED }

    override val kind = EngineKind.RUST

    private val lock = ReentrantLock()
    private val stateChanged = lock.newCondition()
    @Volatile var state = State.UNINITIALIZED
        private set
    private var failure: String? = null
    private var core: RustCore? = null

    // Recorded init arguments (immutable per process once recorded).
    private var masterKey: String? = null
    private var goExtDir: String? = null
    private var goDataDir: String? = null

    // Buffered configuration (R-P4).
    private val downloadDirs = LinkedHashSet<String>()
    private var downloadPriorityJson: String? = null
    private var metadataPriorityJson: String? = null
    private var fallbackIdsJson: String? = null
    private var coverCacheDir: String? = null
    private var coverLease: AutoCloseable? = null

    // ---------------- init (group 1) ----------------

    override fun setAppVersion(version: String) {
        // Intentionally ignored: the engine always gets EngineVersion.SPOTIFLAC_ENGINE_VERSION.
    }

    override fun setExtensionStorageMasterKey(masterKey: String) = lock.withLock {
        this.masterKey = recorded("masterKey", this.masterKey, masterKey)
    }

    override fun initExtensionSystem(extDir: String, dataDir: String) {
        val args = lock.withLock {
            goExtDir = recorded("extDir", goExtDir, canonical(extDir))
            goDataDir = recorded("dataDir", goDataDir, canonical(dataDir))
            when (state) {
                State.READY -> return
                State.INITIALIZING -> null
                State.UNINITIALIZED, State.FAILED -> {
                    val key = masterKey ?: throw IllegalStateException(MISSING_KEY)
                    state = State.INITIALIZING
                    Triple(goExtDir!!, goDataDir!!, key)
                }
            }
        }
        if (args == null) { requireCore(); return }
        val (ext, data, key) = args
        val created = try {
            val copy = EngineDataIsolation.ensureRustCopy(File(ext), File(data))
            factory.create(copy.extensions.canonicalPath, copy.data.canonicalPath, key, EngineVersion.SPOTIFLAC_ENGINE_VERSION)
        } catch (e: Throwable) {
            fail(e); throw e
        }
        lock.withLock {
            try {
                applyConfig(created)
            } catch (e: Throwable) {
                runCatching { created.close() }
                failLocked(e); throw e
            }
            core = created
            state = State.READY
            failure = null
            stateChanged.signalAll()
        }
    }

    override fun loadExtensionsFromDir(dirPath: String): String {
        val c = requireCore()
        val expected = lock.withLock { goExtDir }
        if (canonical(dirPath) != expected) throw IllegalStateException("Extension source directory does not match the initialized owner")
        val result = c.loadAll()
        lock.withLock {
            downloadPriorityJson?.let { runCatching { c.setProviderPriority("download", RustJson.ids(it)) }.onFailure { e -> log("download priority after loadAll: ${e.message}") } }
            metadataPriorityJson?.let { runCatching { c.setProviderPriority("metadata", RustJson.ids(it)) }.onFailure { e -> log("metadata priority after loadAll: ${e.message}") } }
            fallbackIdsJson?.let { runCatching { c.setFallbackProviders(RustJson.idsOrNull(it)) }.onFailure { e -> log("fallback providers after loadAll: ${e.message}") } }
        }
        return result
    }

    // ---------------- extensions ----------------

    override fun loadExtensionFromPath(path: String): String = requireCore().install(path)
    override fun getInstalledExtensions(): String = requireCore().installed()
    override fun setExtensionEnabled(id: String, enabled: Boolean) = requireCore().setEnabled(id, enabled)
    override fun removeExtension(id: String) = requireCore().remove(id)
    override fun getExtensionSettings(id: String): String = requireCore().settings(id)
    override fun setExtensionSettings(id: String, settingsJson: String) = requireCore().updateSettings(id, settingsJson)
    override fun getExtensionPendingAuth(extensionId: String): String = requireCore().pendingAuthJson(extensionId)
    override fun getExtensionHomeFeed(extensionId: String): String = requireCore().homeFeedJson(extensionId)
    override fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String =
        requireCore().customSearchJson(extensionId, query, optionsJson)

    override fun completeSessionGrant(callbackState: String, grant: String): String {
        val c = requireCore()
        val id = try {
            c.resolveCallbackState(callbackState)
        } catch (e: Exception) {
            throw SessionGrantFailure(null, e.message ?: "callback state rejected")
        }
        try {
            c.setSessionGrant(id, grant)
            requireSuccessfulExtensionAction(id, "completeGrant", c.invokeAction(id, "completeGrant"))
        } catch (e: Exception) {
            throw SessionGrantFailure(id, e.message ?: "session grant failed")
        }
        try { c.consumeCallbackState(callbackState) } catch (e: Exception) { log("consumeCallbackState: ${e.message}") }
        return id
    }

    // ---------------- search / metadata / priorities ----------------

    override fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String =
        requireCore().searchMetadataProviders(query, limit, includeExtensions)
    override fun handleUrl(url: String): String = requireCore().handleUrlJson(url)
    override fun findUrlHandler(url: String): String =
        try { requireCore().findUrlHandler(url) ?: "" } catch (e: Exception) { log("findUrlHandler: ${e.message}"); "" }
    override fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String =
        requireCore().getProviderMetadataJson(providerId, resourceType, resourceId)

    override fun getDownloadPriority(): String = priority("download") { downloadPriorityJson }
    override fun getMetadataPriority(): String = priority("metadata") { metadataPriorityJson }

    override fun setDownloadPriority(priorityJson: String) {
        val ids = RustJson.ids(priorityJson)
        lock.withLock { downloadPriorityJson = priorityJson; core?.takeIf { state == State.READY }?.setProviderPriority("download", ids) }
    }

    override fun setMetadataPriority(priorityJson: String) {
        val ids = RustJson.ids(priorityJson)
        lock.withLock { metadataPriorityJson = priorityJson; core?.takeIf { state == State.READY }?.setProviderPriority("metadata", ids) }
    }

    override fun setDownloadFallbackProviderIds(idsJson: String) {
        val ids = RustJson.idsOrNull(idsJson)
        lock.withLock { fallbackIdsJson = idsJson; core?.takeIf { state == State.READY }?.setFallbackProviders(ids) }
    }

    // ---------------- downloads / files ----------------

    override fun downloadByStrategy(requestJson: String): String {
        return try {
            val c = requireCore()
            val request = JSONObject(requestJson)
            val outputDir = request.optString("output_dir", "")
            val result = withGrant(c, outputDir) { c.downloadWithPump(requestJson) }
            indexIfSucceeded(c, outputDir, request, result)
            result
        } catch (e: Exception) {
            val message = e.message ?: e.javaClass.simpleName
            val lower = message.lowercase()
            val type = when {
                "cancel" in lower -> "cancelled"
                lower.startsWith(NOT_READY) -> NOT_READY
                "permission" in lower || "not allowed" in lower || "denied" in lower -> "permission"
                else -> "unknown"
            }
            JSONObject().put("success", false).put("error", message).put("error_type", type).toString()
        }
    }

    override fun getAllDownloadProgress(): String {
        val c = coreOrNull() ?: return RustJson.EMPTY_PROGRESS
        return try { c.allProgress() } catch (e: Exception) { log("allProgress: ${e.message}"); RustJson.EMPTY_PROGRESS }
    }

    override fun cancelDownload(itemId: String) {
        val c = coreOrNull() ?: return
        try { c.cancelDownload(itemId) } catch (e: Exception) { log("cancelDownload: ${e.message}") }
    }

    override fun setDownloadDirectory(path: String) = addDownloadDir(path)

    override fun allowDownloadDir(path: String) {
        try { addDownloadDir(path) } catch (e: Exception) { log("allowDownloadDir: ${e.message}") }
    }

    override fun checkDuplicate(outputDir: String, isrc: String): String {
        val c = requireCore()
        return RustJson.duplicate(withGrant(c, outputDir) { c.checkIsrcExists(outputDir, isrc) })
    }

    override fun getAudioQuality(path: String): String {
        val c = requireCore()
        val p = canonical(path)
        return RustJson.audioQuality(withGrant(c, parentOf(p)) { c.readAudioMetadata(p) })
    }

    override fun editFileMetadata(filePath: String, metadataJson: String): String {
        val c = requireCore()
        val p = canonical(filePath)
        return withGrant(c, parentOf(p)) { c.editFileMetadata(p, metadataJson) }
    }

    override fun reEnrichFile(requestJson: String): String {
        val c = requireCore()
        val request = JSONObject(requestJson)
        val raw = request.optString("file_path", "")
        if (raw.isEmpty()) return c.reenrichFile(requestJson)
        val p = if (request.optBoolean("preview_only", false)) raw else canonical(raw).also { request.put("file_path", it) }
        return withGrant(c, parentOf(p)) { c.reenrichFile(request.toString()) }
    }

    override fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String {
        val c = requireCore()
        if (filePath.isBlank()) return c.getLyricsLrc(spotifyId, trackName, artistName, "", durationMs)
        val p = canonical(filePath)
        return withGrant(c, parentOf(p)) { c.getLyricsLrc(spotifyId, trackName, artistName, p, durationMs) }
    }

    override fun setLibraryCoverCacheDir(cacheDir: String) {
        if (cacheDir.isBlank()) { log("setLibraryCoverCacheDir: blank directory"); return }
        try {
            lock.withLock {
                coverCacheDir = cacheDir
                core?.takeIf { state == State.READY }?.let { openCoverLease(it, cacheDir) }
            }
        } catch (e: Exception) {
            log("setLibraryCoverCacheDir: ${e.message}")
        }
    }

    override fun scanLibraryFolder(folderPath: String): String {
        val c = requireCore()
        return withGrant(c, folderPath) { c.scanLibraryFolder(folderPath) }
    }

    // ---------------- internals ----------------

    private fun recorded(name: String, current: String?, value: String): String {
        if (current != null && current != value) throw IllegalStateException("already_initialized: $name differs from the value recorded for this process")
        return value
    }

    private fun canonical(path: String): String = File(path).canonicalPath
    private fun parentOf(path: String): String = File(path).parent ?: path

    private fun aliases(path: String): List<String> {
        val f = File(path)
        return listOf(f.canonicalPath, f.absolutePath).distinct()
    }

    private fun allowList(): List<String> {
        val all = LinkedHashSet<String>()
        downloadDirs.forEach { all += aliases(it) }
        return all.toList()
    }

    private fun addDownloadDir(path: String) {
        if (path.isBlank()) return
        lock.withLock {
            val dir = File(path).absolutePath
            val added = downloadDirs.add(dir)
            val readyCore = core?.takeIf { state == State.READY }
            try {
                readyCore?.setAllowedDownloadDirectories(allowList())
            } catch (e: Exception) {
                if (added) downloadDirs.remove(dir)
                readyCore?.let { runCatching { it.setAllowedDownloadDirectories(allowList()) } }
                throw e
            }
        }
    }

    /** Must be called with [lock] held. */
    private fun applyConfig(c: RustCore) {
        try {
            c.setAllowedDownloadDirectories(allowList())
        } catch (e: Exception) {
            val empty = emptyList<String>()
            c.setAllowedDownloadDirectories(empty)
            val surviving = LinkedHashSet<String>()
            for (dir in downloadDirs) {
                try {
                    c.setAllowedDownloadDirectories(aliases(dir))
                    surviving += dir
                } catch (badDir: Exception) {
                    log("download directory unavailable: $dir: ${badDir.message}")
                }
            }
            downloadDirs.clear()
            downloadDirs.addAll(surviving)
            try {
                c.setAllowedDownloadDirectories(allowList())
            } catch (combined: Exception) {
                log("download directories unavailable together: ${combined.message}")
                downloadDirs.clear()
                c.setAllowedDownloadDirectories(empty)
            }
        }
        fallbackIdsJson?.let { c.setFallbackProviders(RustJson.idsOrNull(it)) }
        downloadPriorityJson?.let { c.setProviderPriority("download", RustJson.ids(it)) }
        metadataPriorityJson?.let { c.setProviderPriority("metadata", RustJson.ids(it)) }
        coverCacheDir?.let { openCoverLease(c, it) }
    }

    /** Must be called with [lock] held. */
    private fun openCoverLease(c: RustCore, dir: String) {
        val lease = c.grantDownloadDirectories(aliases(dir))
        try {
            c.setLibraryCoverCacheDirectory(dir)
        } catch (e: Exception) {
            lease.close(); throw e
        }
        coverLease?.let { runCatching { it.close() } }
        coverLease = lease
    }

    private fun <T> withGrant(c: RustCore, dir: String, block: () -> T): T {
        if (dir.isBlank() || canonical(dir) == "/") return block()
        val lease = c.grantDownloadDirectories(aliases(dir))
        try {
            return block()
        } finally {
            runCatching { lease.close() }
        }
    }

    private fun indexIfSucceeded(c: RustCore, outputDir: String, request: JSONObject, result: String) {
        if (outputDir.isBlank()) return
        try {
            val r = JSONObject(result)
            if (!r.optBoolean("success", false)) return
            val filePath = r.optString("file_path", "")
            val isrc = r.optString("isrc", "").ifBlank { request.optString("isrc", "") }
            if (filePath.isNotBlank() && isrc.isNotBlank()) c.addToIsrcIndex(outputDir, isrc, filePath)
        } catch (e: Exception) {
            log("addToIsrcIndex: ${e.message}")
        }
    }

    private fun priority(kind: String, buffered: () -> String?): String {
        val c = coreOrNull() ?: return lock.withLock { buffered() } ?: "[]"
        return RustJson.priorities(c.providerPriorities(), kind)
    }

    private fun coreOrNull(): RustCore? = lock.withLock { core.takeIf { state == State.READY } }

    private fun requireCore(): RustCore = lock.withLock {
        var remaining = TimeUnit.MILLISECONDS.toNanos(readyTimeoutMs)
        while (state != State.READY) {
            if (state == State.FAILED) throw IllegalStateException("$NOT_READY: ${failure ?: "initialization failed"}")
            if (remaining <= 0) throw IllegalStateException("$NOT_READY: timed out waiting for initialization")
            remaining = stateChanged.awaitNanos(remaining)
        }
        core!!
    }

    private fun fail(e: Throwable) = lock.withLock { failLocked(e) }

    private fun failLocked(e: Throwable) {
        state = State.FAILED
        failure = e.message ?: e.javaClass.simpleName
        stateChanged.signalAll()
    }
}
