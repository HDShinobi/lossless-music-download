package xyz.losslessmusic.app.engine

/** A session-grant exchange failed; [extensionId] is null when the callback state itself was rejected. */
class SessionGrantFailure(val extensionId: String?, message: String) : Exception(message)

/**
 * The native engine contract, in the Go-era shapes the MethodChannel and Dart already expect
 * (see spec §3.1). Methods that throw in Go throw here (→ Dart PlatformException "BACKEND_ERROR");
 * getAllDownloadProgress, cancelDownload, allowDownloadDir, findUrlHandler, setLibraryCoverCacheDir
 * and setAppVersion never throw. downloadByStrategy reports failures in-band ({"success":false,…}).
 * All methods block; call them off the main thread.
 */
interface NativeEngine {
    // init (group 1) — call order today: setAppVersion (Kotlin), setExtensionStorageMasterKey, initExtensionSystem
    fun setAppVersion(version: String)
    fun setExtensionStorageMasterKey(masterKey: String)
    fun initExtensionSystem(extDir: String, dataDir: String)
    fun loadExtensionsFromDir(dirPath: String): String

    // extensions
    fun loadExtensionFromPath(path: String): String
    fun getInstalledExtensions(): String
    fun setExtensionEnabled(id: String, enabled: Boolean)
    fun removeExtension(id: String)
    fun getExtensionSettings(id: String): String
    fun setExtensionSettings(id: String, settingsJson: String)
    fun getExtensionPendingAuth(extensionId: String): String
    fun getExtensionHomeFeed(extensionId: String): String
    fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String
    /** Resolves the deep-link callback state, stores the grant and completes it; returns the extension id. */
    fun completeSessionGrant(callbackState: String, grant: String): String

    // search / metadata / priorities
    fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String
    fun handleUrl(url: String): String
    fun findUrlHandler(url: String): String
    fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String
    fun getDownloadPriority(): String
    fun setDownloadPriority(priorityJson: String)
    fun getMetadataPriority(): String
    fun setMetadataPriority(priorityJson: String)
    fun setDownloadFallbackProviderIds(idsJson: String)

    // downloads / files
    fun downloadByStrategy(requestJson: String): String
    fun getAllDownloadProgress(): String
    fun cancelDownload(itemId: String)
    fun setDownloadDirectory(path: String)
    fun allowDownloadDir(path: String)
    fun checkDuplicate(outputDir: String, isrc: String): String
    fun getAudioQuality(path: String): String
    fun editFileMetadata(filePath: String, metadataJson: String): String
    fun reEnrichFile(requestJson: String): String
    fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String
    fun setLibraryCoverCacheDir(cacheDir: String)
    fun scanLibraryFolder(folderPath: String): String
}
