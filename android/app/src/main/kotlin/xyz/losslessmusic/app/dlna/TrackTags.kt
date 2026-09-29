package xyz.losslessmusic.app.dlna

import java.io.File

data class TrackTags(
    val title: String = "", val artist: String = "", val album: String = "", val albumArtist: String = "",
    val genre: String = "", val trackNumber: Int = 0, val durationSec: Int = 0,
    val sampleRate: Int = 0, val bitDepth: Int = 0, val bitrateKbps: Int = 0,
)

interface MetadataProvider {
    fun readTags(absPath: String): TrackTags?
    fun readCover(absPath: String): Pair<ByteArray, String>?
}

internal class TagCache {
    private data class Entry(val modified: Long, val tags: TrackTags?)
    private val entries = mutableMapOf<String, Entry>()

    fun get(absPath: String, provider: MetadataProvider): TrackTags? {
        val modified = File(absPath).lastModified()
        val cached = synchronized(this) { entries[absPath] }
        if (cached != null && cached.modified == modified) return cached.tags
        return provider.readTags(absPath).also { tags ->
            synchronized(this) { entries[absPath] = Entry(modified, tags) }
        }
    }
}
