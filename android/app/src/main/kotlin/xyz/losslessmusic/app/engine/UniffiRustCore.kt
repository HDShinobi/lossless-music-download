package xyz.losslessmusic.app.engine

import com.spotiflac.backend.CancellationDomain
import com.spotiflac.backend.CancellationRegistry
import com.spotiflac.backend.ExtensionEnvironment
import com.spotiflac.backend.ExtensionManager
import com.spotiflac.backend.LyricsRequest
import com.spotiflac.backend.RequestLease
import com.zarz.spotiflac.CoreExtensionExecution
import com.zarz.spotiflac.CoreFFmpegCommand
import com.zarz.spotiflac.parseCoreFFmpegCommands
import com.zarz.spotiflac.withCoreFFmpegExecution
import java.util.UUID

/** RustCore over the real UniFFI engine. Every call blocks; never call from the main thread. */
class UniffiRustCore private constructor(private val manager: ExtensionManager) : RustCore {
    companion object {
        private const val TIMEOUT_MS: ULong = 30_000uL
        private const val POST_PROCESS_TIMEOUT_MS: ULong = 120_000uL

        val FACTORY = RustCoreFactory { source, data, masterKey, appVersion ->
            UniffiRustCore(ExtensionManager.withLyricsSettings(source, data, masterKey, appVersion, TIMEOUT_MS, "[]", "{}"))
        }
    }

    private val requests = CancellationRegistry(CancellationDomain.EXTENSION_REQUEST)

    private inline fun <T> env(block: (ExtensionEnvironment) -> T): T = manager.environment().use(block)

    private inline fun <T> withLease(block: (RequestLease) -> T): T {
        val lease = requests.acquire(UUID.randomUUID().toString())
        try {
            return block(lease)
        } finally {
            try { lease.release() } finally { lease.close() }
        }
    }

    override fun loadAll(): String = manager.loadAll()
    override fun installed(): String = manager.installed()
    override fun install(packagePath: String): String = manager.install(packagePath)
    override fun setEnabled(extensionId: String, enabled: Boolean) = manager.setEnabled(extensionId, enabled)
    override fun remove(extensionId: String) = manager.remove(extensionId)
    override fun settings(extensionId: String): String = env { it.settings(extensionId) }
    override fun updateSettings(extensionId: String, settingsJson: String) = manager.updateSettings(extensionId, settingsJson)
    override fun pendingAuthJson(extensionId: String): String = manager.getExtensionPendingAuthJson(extensionId)
    override fun invokeAction(extensionId: String, action: String): String = manager.invokeAction(extensionId, action)
    override fun homeFeedJson(extensionId: String): String = withLease { manager.getExtensionHomeFeedJson(extensionId, it) }
    override fun customSearchJson(extensionId: String, query: String, optionsJson: String): String =
        withLease { manager.customSearchJson(extensionId, query, optionsJson, it) }
    override fun resolveCallbackState(state: String): String = env { it.resolveCallbackState(state) }
    override fun setSessionGrant(extensionId: String, grant: String) = env { it.setSessionGrant(extensionId, grant) }

    override fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean): String =
        manager.searchMetadataProviders(query, limit, includeExtensions, "", TIMEOUT_MS)
    override fun handleUrlJson(url: String): String = manager.handleUrlJson(url)
    override fun findUrlHandler(url: String): String? = manager.findUrlHandler(url)
    override fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String): String =
        manager.getProviderMetadataJson(providerId, resourceType, resourceId, null)
    override fun providerPriorities(): String = manager.providerPriorities()
    override fun setProviderPriority(kind: String, ids: List<String>) = manager.setProviderPriority(kind, ids)
    override fun setFallbackProviders(ids: List<String>?) = manager.setFallbackProviders(ids)

    override fun downloadWithPump(requestJson: String): String {
        val commands = env { it.ffmpegCommands() }
        val execution = object : CoreExtensionExecution {
            override fun download(requestJson: String): String = manager.downloadByStrategy(requestJson)
            override fun postProcess(inputJson: String, metadataJson: String): String =
                manager.runPostProcessing(inputJson, metadataJson, POST_PROCESS_TIMEOUT_MS)
            override fun waitPending(timeoutMs: Long): List<CoreFFmpegCommand> =
                parseCoreFFmpegCommands(commands.waitPending(timeoutMs))
            override fun commandIsActive(commandId: String): Boolean = commands.getCommand(commandId).isNotEmpty()
            override fun complete(commandId: String, success: Boolean, output: String, error: String) {
                commands.complete(commandId, success, output, error)
            }
            override fun close() = commands.close()
        }
        // withCoreFFmpegExecution runs FFmpeg commands through NativeDownloadFinalizer.runFFmpegArguments
        // (our EngineShims → ffmpeg-kit) on a pump thread and closes `execution` when done.
        return withCoreFFmpegExecution(execution) { it.download(requestJson) }
    }

    override fun allProgress(): String = env { e -> e.downloadState().use { it.allProgress() } }
    override fun cancelDownload(itemId: String) = env { e -> e.downloadState().use { it.cancelDownload(itemId) } }
    override fun setAllowedDownloadDirectories(directories: List<String>) = env { it.setAllowedDownloadDirectories(directories) }
    override fun grantDownloadDirectories(directories: List<String>): AutoCloseable {
        val scope = env { it.grantDownloadDirectories(directories) }
        return AutoCloseable { try { scope.release() } finally { scope.close() } }
    }
    override fun checkIsrcExists(directory: String, isrc: String): String = env { it.checkIsrcExists(directory, isrc, null) }
    override fun addToIsrcIndex(directory: String, isrc: String, path: String) = env { it.addToIsrcIndex(directory, isrc, path, null) }
    override fun readAudioMetadata(path: String): String = manager.readAudioMetadata(path, "", "", null)
    override fun editFileMetadata(path: String, metadataJson: String): String = manager.editFileMetadata(path, metadataJson, null)
    override fun reenrichFile(requestJson: String): String = manager.reenrichFile(requestJson, null)
    override fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long): String =
        manager.getLyricsLrc(LyricsRequest(spotifyId, track, artist, filePath, durationMs), null)
    override fun setLibraryCoverCacheDirectory(directory: String) = manager.setLibraryCoverCacheDirectory(directory)
    override fun scanLibraryFolder(folder: String): String = manager.scanLibraryFolder(folder, null)

    override fun close() {
        try { requests.shutdown() } catch (_: Exception) {}
        requests.close()
        try { manager.shutdown() } catch (_: Exception) {}
        manager.close()
    }
}
