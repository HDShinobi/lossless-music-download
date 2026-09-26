package xyz.losslessmusic.app.engine

import xyz.losslessmusic.backend.bridge.Bridge

/** Today's engine: 1:1 delegation to the gomobile Bridge. Behaviour must not change. */
object GoEngine : NativeEngine {
    override val kind = EngineKind.GO

    override fun setAppVersion(version: String) = Bridge.setAppVersion(version)
    override fun setExtensionStorageMasterKey(masterKey: String) = Bridge.setExtensionStorageMasterKey(masterKey)
    override fun initExtensionSystem(extDir: String, dataDir: String) = Bridge.initExtensionSystem(extDir, dataDir)
    override fun loadExtensionsFromDir(dirPath: String): String = Bridge.loadExtensionsFromDir(dirPath)

    override fun loadExtensionFromPath(path: String): String = Bridge.loadExtensionFromPath(path)
    override fun getInstalledExtensions(): String = Bridge.getInstalledExtensions()
    override fun setExtensionEnabled(id: String, enabled: Boolean) = Bridge.setExtensionEnabledByID(id, enabled)
    override fun removeExtension(id: String) = Bridge.removeExtensionByID(id)
    override fun getExtensionSettings(id: String): String = Bridge.getExtensionSettingsJSON(id)
    override fun setExtensionSettings(id: String, settingsJson: String) = Bridge.setExtensionSettingsJSON(id, settingsJson)
    override fun getExtensionPendingAuth(extensionId: String): String = Bridge.getExtensionPendingAuthJSON(extensionId)
    override fun getExtensionHomeFeed(extensionId: String): String = Bridge.getExtensionHomeFeedJSON(extensionId)
    override fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String =
        Bridge.customSearchWithExtensionJSON(extensionId, query, optionsJson)

    override fun completeSessionGrant(callbackState: String, grant: String): String {
        // `state` is a one-time nonce (not the extension id): consume it first (v0.9.1 fix).
        val extensionId = try {
            Bridge.consumeExtensionCallbackState(callbackState)
        } catch (e: Exception) {
            throw SessionGrantFailure(null, e.message ?: "callback state rejected")
        }
        try {
            Bridge.setExtensionSessionGrantByID(extensionId, grant)
            Bridge.invokeExtensionActionJSON(extensionId, "completeGrant")
        } catch (e: Exception) {
            throw SessionGrantFailure(extensionId, e.message ?: "session grant failed")
        }
        return extensionId
    }

    override fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String =
        Bridge.searchTracksWithMetadataProvidersJSON(query, limit, includeExtensions)
    override fun handleUrl(url: String): String = Bridge.handleURLWithExtensionJSON(url)
    override fun findUrlHandler(url: String): String = Bridge.findURLHandlerJSON(url)
    override fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String =
        Bridge.getProviderMetadataJSON(providerId, resourceType, resourceId)
    override fun getDownloadPriority(): String = Bridge.getProviderPriorityJSON()
    override fun setDownloadPriority(priorityJson: String) = Bridge.setProviderPriorityJSON(priorityJson)
    override fun getMetadataPriority(): String = Bridge.getMetadataProviderPriorityJSON()
    override fun setMetadataPriority(priorityJson: String) = Bridge.setMetadataProviderPriorityJSON(priorityJson)
    override fun setDownloadFallbackProviderIds(idsJson: String) = Bridge.setExtensionFallbackProviderIDsJSON(idsJson)

    override fun downloadByStrategy(requestJson: String): String = Bridge.downloadByStrategy(requestJson)
    override fun getAllDownloadProgress(): String = Bridge.getAllDownloadProgress()
    override fun cancelDownload(itemId: String) = Bridge.cancelDownload(itemId)
    override fun setDownloadDirectory(path: String) = Bridge.setDownloadDirectory(path)
    override fun allowDownloadDir(path: String) = Bridge.allowDownloadDir(path)
    override fun checkDuplicate(outputDir: String, isrc: String): String = Bridge.checkDuplicate(outputDir, isrc)
    override fun getAudioQuality(path: String): String = Bridge.getAudioQualityJSON(path)
    override fun editFileMetadata(filePath: String, metadataJson: String): String = Bridge.editFileMetadata(filePath, metadataJson)
    override fun reEnrichFile(requestJson: String): String = Bridge.reEnrichFile(requestJson)
    override fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String =
        Bridge.getLyricsLRC(spotifyId, trackName, artistName, filePath, durationMs)
    override fun setLibraryCoverCacheDir(cacheDir: String) = Bridge.setLibraryCoverCacheDir(cacheDir)
    override fun scanLibraryFolder(folderPath: String): String = Bridge.scanLibraryFolderJSON(folderPath)
}
