package xyz.losslessmusic.app.dlna

import java.io.File
import java.security.MessageDigest
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

class EngineMetadataProvider(
    private val readMetadataJson: (String) -> String,
    private val extractCover: (audioPath: String, outPath: String) -> Unit,
    private val coverCacheDir: File,
    private val thumbnail: ((src: File, dst: File, maxPx: Int) -> Boolean)? = null,
) : MetadataProvider {
    companion object {
        const val THUMBNAIL_MAX_PX = 600
    }

    private val coverLocks = ConcurrentHashMap<String, Any>()
    private val missingCovers = ConcurrentHashMap.newKeySet<String>()
    override fun readTags(absPath: String): TrackTags? = try {
        val raw = readMetadataJson(absPath)
        if (raw.isBlank()) null else JSONObject(raw).let { data ->
            TrackTags(
                title = data.optString("trackName"), artist = data.optString("artistName"),
                album = data.optString("albumName"), albumArtist = data.optString("albumArtist"),
                genre = data.optString("genre"), trackNumber = data.optInt("trackNumber"),
                durationSec = data.optInt("duration"), sampleRate = data.optInt("sampleRate"),
                bitDepth = data.optInt("bitDepth"), bitrateKbps = data.optInt("bitrate"),
            )
        }
    } catch (_: Exception) { null }

    override fun readCover(absPath: String): Pair<ByteArray, String>? {
        return try {
            val digest = MessageDigest.getInstance("SHA-1").digest(absPath.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            val key = "$digest-${File(absPath).lastModified()}"
            val target = File(coverCacheDir, "$key.img")
            val thumb = File(coverCacheDir, "$key-t$THUMBNAIL_MAX_PX.jpg")
            // Completed thumbnails are immutable and published with an atomic move.
            if (thumb.isFile && thumb.length() > 0L) return thumb.readBytes() to "image/jpeg"
            synchronized(coverLocks.computeIfAbsent(key) { Any() }) {
                if (thumb.isFile && thumb.length() > 0L) return thumb.readBytes() to "image/jpeg"
                if (target.absolutePath in missingCovers) return null
                if (!target.exists()) {
                    coverCacheDir.mkdirs()
                    try {
                        extractCover(absPath, target.absolutePath)
                    } catch (_: Exception) {
                        missingCovers += target.absolutePath
                        return null
                    }
                }
                if (!target.isFile || target.length() == 0L) {
                    missingCovers += target.absolutePath
                    return null
                }
                if (thumbnail != null) {
                    var temp: File? = null
                    try {
                        temp = File.createTempFile("$key-", ".tmp", coverCacheDir)
                        if (thumbnail.invoke(target, temp, THUMBNAIL_MAX_PX) && temp.isFile && temp.length() > 0L) {
                            Files.move(temp.toPath(), thumb.toPath(), StandardCopyOption.ATOMIC_MOVE,
                                StandardCopyOption.REPLACE_EXISTING)
                            target.delete()
                            return thumb.readBytes() to "image/jpeg"
                        }
                    } catch (_: Exception) {
                        // Keep the original and retry thumbnailing on the next request.
                    } finally {
                        temp?.delete()
                    }
                }
                val bytes = target.readBytes()
                val mime = when {
                    bytes.size >= 3 && bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() && bytes[2] == 0xff.toByte() -> "image/jpeg"
                    bytes.size >= 4 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() && bytes[2] == 0x4e.toByte() && bytes[3] == 0x47.toByte() -> "image/png"
                    bytes.size >= 12 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> "image/webp"
                    else -> "image/jpeg"
                }
                bytes to mime
            }
        } catch (_: Exception) { null }
    }
}
