package xyz.losslessmusic.app.engine

/** Records calls; return values are configurable per test. Thread-safe enough for these tests. */
class FakeRustCore : RustCore {
    val calls = mutableListOf<String>()
    var openLeases = 0
    var leasesOpened = 0
    var allowed: List<String> = emptyList()
    val badDownloadDirs = mutableSetOf<String>()
    var priorities = "{\"download\":[],\"metadata\":[]}"
    var progress = "{\"items\":{\"a\":{\"item_id\":\"a\",\"progress\":0.5}}}"
    var downloadResult = "{\"success\":true,\"file_path\":\"/out/a.flac\",\"isrc\":\"ISRC1\"}"
    var downloadThrows: Exception? = null
    var isrcPath = ""
    var audioMetadata = "{\"bitDepth\":16,\"sampleRate\":44100,\"duration\":10,\"format\":\"flac\"}"
    var resolveResult: () -> String = { "qobuz-web" }
    var actionResult = "{\"success\":true}"
    var findResult: String? = "qobuz-web"
    var closed = false

    private fun rec(s: String) { synchronized(calls) { calls += s } }

    override fun loadAll() = "{\"loaded\":[],\"errors\":[]}".also { rec("loadAll") }
    override fun installed() = "[]".also { rec("installed") }
    override fun install(packagePath: String) = "{}".also { rec("install:$packagePath") }
    override fun setEnabled(extensionId: String, enabled: Boolean) = rec("setEnabled:$extensionId:$enabled")
    override fun remove(extensionId: String) = rec("remove:$extensionId")
    override fun settings(extensionId: String) = "{}".also { rec("settings:$extensionId") }
    override fun updateSettings(extensionId: String, settingsJson: String) = rec("updateSettings:$extensionId")
    override fun pendingAuthJson(extensionId: String) = "".also { rec("pendingAuth:$extensionId") }
    override fun invokeAction(extensionId: String, action: String) = actionResult.also { rec("invokeAction:$extensionId:$action") }
    override fun homeFeedJson(extensionId: String) = "{}".also { rec("homeFeed:$extensionId") }
    override fun customSearchJson(extensionId: String, query: String, optionsJson: String) = "[]".also { rec("customSearch:$extensionId:$query") }
    override fun resolveCallbackState(state: String) = resolveResult().also { rec("resolve:$state") }
    override fun setSessionGrant(extensionId: String, grant: String) = rec("setSessionGrant:$extensionId")
    override fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean) = "[]".also { rec("search:$query:$limit:$includeExtensions") }
    override fun handleUrlJson(url: String) = "{}".also { rec("handleUrl:$url") }
    override fun findUrlHandler(url: String) = findResult.also { rec("findUrlHandler:$url") }
    override fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String) = "{}".also { rec("providerMetadata:$providerId") }
    override fun providerPriorities() = priorities.also { rec("providerPriorities") }
    override fun setProviderPriority(kind: String, ids: List<String>) = rec("setProviderPriority:$kind:${ids.joinToString(",")}")
    override fun setFallbackProviders(ids: List<String>?) = rec("setFallbackProviders:${ids?.joinToString(",")}")
    override fun downloadWithPump(requestJson: String): String { rec("download"); downloadThrows?.let { throw it }; return downloadResult }
    override fun allProgress() = progress.also { rec("allProgress") }
    override fun cancelDownload(itemId: String) = rec("cancel:$itemId")
    override fun setAllowedDownloadDirectories(directories: List<String>) {
        if (directories.any { it in badDownloadDirs }) throw IllegalStateException("unavailable download directory")
        allowed = directories
        rec("setAllowed")
    }
    override fun grantDownloadDirectories(directories: List<String>): AutoCloseable {
        synchronized(calls) { openLeases++; leasesOpened++; calls += "grant:${directories.first()}" }
        return AutoCloseable { synchronized(calls) { openLeases--; calls += "release" } }
    }
    override fun checkIsrcExists(directory: String, isrc: String) = isrcPath.also { rec("checkIsrc:$directory:$isrc") }
    override fun addToIsrcIndex(directory: String, isrc: String, path: String) = rec("addIsrc:$directory:$isrc:$path")
    override fun readAudioMetadata(path: String) = audioMetadata.also { rec("readAudio:$path") }
    override fun editFileMetadata(path: String, metadataJson: String) = "{\"success\":true,\"method\":\"native\"}".also { rec("edit:$path") }
    override fun reenrichFile(requestJson: String) = "{}".also { rec("reenrich:$requestJson") }
    override fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long) = "[00:00.00]x".also { rec("lyrics:$track") }
    override fun setLibraryCoverCacheDirectory(directory: String) = rec("coverCache:$directory")
    override fun scanLibraryFolder(folder: String) = "[]".also { rec("scan:$folder") }
    override fun close() { closed = true; rec("close") }
}
