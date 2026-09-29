package xyz.losslessmusic.app.engine

/**
 * The slice of the UniFFI API RustEngine uses, in plain Kotlin types so RustEngine can be tested
 * with a fake. One implementation talks to the real engine: UniffiRustCore.
 */
interface RustCore : AutoCloseable {
    // extensions
    fun loadAll(): String
    fun installed(): String
    fun install(packagePath: String): String
    fun setEnabled(extensionId: String, enabled: Boolean)
    fun remove(extensionId: String)
    fun settings(extensionId: String): String
    fun updateSettings(extensionId: String, settingsJson: String)
    fun pendingAuthJson(extensionId: String): String
    fun invokeAction(extensionId: String, action: String): String
    fun homeFeedJson(extensionId: String): String
    fun customSearchJson(extensionId: String, query: String, optionsJson: String): String
    fun resolveCallbackState(state: String): String
    fun consumeCallbackState(state: String): String
    fun setSessionGrant(extensionId: String, grant: String)

    // search / metadata / priorities
    fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean): String
    fun handleUrlJson(url: String): String
    fun findUrlHandler(url: String): String?
    fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String): String
    fun providerPriorities(): String
    fun setProviderPriority(kind: String, ids: List<String>)
    fun setFallbackProviders(ids: List<String>?)

    // downloads / files
    fun downloadWithPump(requestJson: String): String
    fun allProgress(): String
    fun cancelDownload(itemId: String)
    fun setAllowedDownloadDirectories(directories: List<String>)
    /** Scoped directory lease; close() releases it. */
    fun grantDownloadDirectories(directories: List<String>): AutoCloseable
    fun checkIsrcExists(directory: String, isrc: String): String
    fun addToIsrcIndex(directory: String, isrc: String, path: String)
    fun readAudioMetadata(path: String): String
    fun extractCoverToFile(audioPath: String, outputPath: String)
    fun editFileMetadata(path: String, metadataJson: String): String
    fun reenrichFile(requestJson: String): String
    fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long): String
    fun embedLyricsToFile(path: String, lyrics: String): String
    fun setLibraryCoverCacheDirectory(directory: String)
    fun scanLibraryFolder(folder: String): String
}

fun interface RustCoreFactory {
    fun create(sourceDirectory: String, dataDirectory: String, masterKey: String, appVersion: String): RustCore
}
