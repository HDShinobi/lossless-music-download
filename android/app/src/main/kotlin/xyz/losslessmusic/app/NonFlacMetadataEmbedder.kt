package xyz.losslessmusic.app

import android.content.Context
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import org.json.JSONObject
import xyz.losslessmusic.backend.bridge.Bridge
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

/**
 * Tags NON-FLAC downloads (Opus/M4A/MP3) with metadata, cover art, and
 * lyrics, using FFmpegKit's native Android classes directly (no Flutter
 * engine dependency, so this works from the background download service).
 * FLAC is tagged natively in go_backend, so this is only invoked for lossy
 * formats.
 */
object NonFlacMetadataEmbedder {

    fun isEmbeddable(filePath: String): Boolean {
        val ext = extOf(filePath)
        return ext == "opus" || ext == "m4a" || ext == "mp3" || ext == "ogg"
    }

    private fun extOf(path: String): String {
        val dot = path.lastIndexOf('.')
        if (dot < 0 || dot == path.length - 1) return ""
        return path.substring(dot + 1).lowercase()
    }

    fun embed(context: Context, filePath: String, requestJson: String) {
        val request = try { JSONObject(requestJson) } catch (_: Exception) { return }
        if (!request.optBoolean("embed_metadata", true)) return
        if (!File(filePath).exists()) return

        val metadata = buildVorbisMetadata(request)
        if (request.optBoolean("embed_lyrics", true)) {
            fetchLyrics(request)?.let { metadata["LYRICS"] = it }
        }
        var coverPath: String? = null
        if (request.optBoolean("embed_max_quality_cover", true)) {
            val coverUrl = request.optString("cover_url", "")
            if (coverUrl.isNotEmpty()) coverPath = downloadCoverToTemp(context, coverUrl)
        }

        try {
            when (extOf(filePath)) {
                "opus", "ogg" -> embedOpus(context, filePath, metadata, coverPath)
                "m4a" -> embedM4a(context, filePath, metadata, coverPath)
                "mp3" -> embedMp3(context, filePath, metadata, coverPath)
            }
        } finally {
            coverPath?.let { try { File(it).delete() } catch (_: Exception) {} }
        }
    }

    private fun buildVorbisMetadata(request: JSONObject): MutableMap<String, String> {
        val out = mutableMapOf<String, String>()
        fun put(key: String, value: String?) { if (!value.isNullOrEmpty()) out[key] = value }
        put("TITLE", request.optString("track_name", ""))
        put("ARTIST", request.optString("artist_name", ""))
        put("ALBUM", request.optString("album_name", ""))
        put("ALBUMARTIST", request.optString("album_artist", ""))
        put("DATE", request.optString("release_date", ""))
        put("ISRC", request.optString("isrc", ""))
        put("GENRE", request.optString("genre", ""))
        put("ORGANIZATION", request.optString("label", ""))
        put("COPYRIGHT", request.optString("copyright", ""))
        put("COMPOSER", request.optString("composer", ""))
        val trackNumber = request.optInt("track_number", 0)
        if (trackNumber > 0) out["TRACKNUMBER"] = trackNumber.toString()
        val discNumber = request.optInt("disc_number", 0)
        if (discNumber > 0) out["DISCNUMBER"] = discNumber.toString()
        return out
    }

    private fun fetchLyrics(request: JSONObject): String? {
        return try {
            val spotifyId = request.optString("spotify_id", "")
            val lrc = Bridge.getLyricsLRC(
                spotifyId,
                request.optString("track_name", ""),
                request.optString("artist_name", ""),
                "",
                request.optLong("duration_ms", 0L),
            )
            val trimmed = lrc.trim()
            if (trimmed.isEmpty() || trimmed == "[instrumental:true]") null else trimmed
        } catch (_: Exception) {
            null
        }
    }

    private fun downloadCoverToTemp(context: Context, url: String): String? {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.inputStream.use { input ->
                val ext = if (url.lowercase().contains(".png")) "png" else "jpg"
                val file = File(context.cacheDir, "cover_${System.currentTimeMillis()}.$ext")
                file.outputStream().use { output -> input.copyTo(output) }
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun appendMetadataArgs(args: MutableList<String>, metadata: Map<String, String>) {
        for ((key, value) in metadata) {
            args.add("-metadata")
            args.add("$key=$value")
        }
    }

    private fun coverPictureBlockBase64(coverPath: String): String? {
        return try {
            val bytes = File(coverPath).readBytes()
            val mime = if (coverPath.lowercase().endsWith(".png")) "image/png" else "image/jpeg"
            val mimeBytes = mime.toByteArray(Charsets.UTF_8)
            val block = java.io.ByteArrayOutputStream()
            fun writeU32(v: Int) {
                block.write((v ushr 24) and 0xFF); block.write((v ushr 16) and 0xFF)
                block.write((v ushr 8) and 0xFF); block.write(v and 0xFF)
            }
            writeU32(3) // picture type: front cover
            writeU32(mimeBytes.size); block.write(mimeBytes)
            writeU32(0) // description length
            writeU32(0); writeU32(0); writeU32(0); writeU32(0) // width, height, depth, colors
            writeU32(bytes.size); block.write(bytes)
            Base64.getEncoder().encodeToString(block.toByteArray())
        } catch (_: Exception) {
            null
        }
    }

    private fun runAndReplace(args: List<String>, tempOutput: String, originalPath: String) {
        val session = FFmpegKit.executeWithArguments(args.toTypedArray())
        val temp = File(tempOutput)
        if (ReturnCode.isSuccess(session.returnCode) && temp.exists()) {
            val original = File(originalPath)
            if (original.exists()) original.delete()
            temp.copyTo(original, overwrite = true)
            temp.delete()
        } else {
            if (temp.exists()) temp.delete()
        }
    }

    private fun embedOpus(context: Context, opusPath: String, metadata: Map<String, String>, coverPath: String?) {
        val tempOutput = File(context.cacheDir, "temp_embed_${System.currentTimeMillis()}.opus").absolutePath
        val args = mutableListOf(
            "-v", "error", "-hide_banner",
            "-i", opusPath,
            "-map", "0:a",
            "-map_metadata", "-1",
            "-map_metadata:s:a", "-1",
            "-c:a", "copy",
        )
        appendMetadataArgs(args, metadata)
        if (coverPath != null) {
            coverPictureBlockBase64(coverPath)?.let {
                args.add("-metadata"); args.add("METADATA_BLOCK_PICTURE=$it")
            }
        }
        args.add(tempOutput); args.add("-y")
        runAndReplace(args, tempOutput, opusPath)
    }

    private fun embedM4a(context: Context, m4aPath: String, metadata: Map<String, String>, coverPath: String?) {
        val tempOutput = File(context.cacheDir, "temp_embed_${System.currentTimeMillis()}.m4a").absolutePath
        val hasCover = coverPath != null
        val args = mutableListOf("-v", "error", "-hide_banner", "-i", m4aPath)
        if (hasCover) { args.add("-i"); args.add(coverPath!!) }
        args.add("-map"); args.add("0:a"); args.add("-c:a"); args.add("copy")
        args.add("-map_metadata"); args.add("-1")
        if (hasCover) {
            args.add("-map"); args.add("1:v")
            args.add("-c:v"); args.add("copy")
            args.add("-disposition:v:0"); args.add("attached_pic")
            args.add("-metadata:s:v"); args.add("title=Album cover")
            args.add("-metadata:s:v"); args.add("comment=Cover (front)")
            args.add("-f"); args.add("mp4")
        }
        appendMetadataArgs(args, convertToM4aTags(metadata))
        args.add(tempOutput); args.add("-y")
        runAndReplace(args, tempOutput, m4aPath)
    }

    private fun embedMp3(context: Context, mp3Path: String, metadata: Map<String, String>, coverPath: String?) {
        val tempOutput = File(context.cacheDir, "temp_embed_${System.currentTimeMillis()}.mp3").absolutePath
        val hasCover = coverPath != null
        val args = mutableListOf("-v", "error", "-hide_banner", "-i", mp3Path)
        if (hasCover) { args.add("-i"); args.add(coverPath!!) }
        args.add("-map"); args.add("0:a"); args.add("-map_metadata"); args.add("-1")
        if (hasCover) {
            args.add("-map"); args.add("1:0")
            args.add("-c:v:0"); args.add("copy")
            args.add("-metadata:s:v"); args.add("title=Album cover")
            args.add("-metadata:s:v"); args.add("comment=Cover (front)")
        }
        args.add("-c:a"); args.add("copy")
        appendMetadataArgs(args, convertToId3Tags(metadata))
        args.add("-id3v2_version"); args.add("3"); args.add(tempOutput); args.add("-y")
        runAndReplace(args, tempOutput, mp3Path)
    }

    private fun convertToM4aTags(metadata: Map<String, String>): Map<String, String> {
        val map = mapOf(
            "TITLE" to "title", "ARTIST" to "artist", "ALBUM" to "album",
            "ALBUMARTIST" to "album_artist", "TRACKNUMBER" to "track", "DISCNUMBER" to "disc",
            "DATE" to "date", "GENRE" to "genre", "ISRC" to "isrc", "COMPOSER" to "composer",
            "COPYRIGHT" to "copyright", "ORGANIZATION" to "organization", "LYRICS" to "lyrics",
        )
        return metadata.mapNotNull { (k, v) -> map[k]?.let { it to v } }.toMap()
    }

    private fun convertToId3Tags(metadata: Map<String, String>): Map<String, String> {
        val map = mapOf(
            "TITLE" to "title", "ARTIST" to "artist", "ALBUM" to "album",
            "ALBUMARTIST" to "album_artist", "TRACKNUMBER" to "track", "DISCNUMBER" to "disc",
            "DATE" to "date", "GENRE" to "genre", "ISRC" to "TSRC", "COMPOSER" to "composer",
            "LYRICS" to "lyrics",
        )
        return metadata.mapNotNull { (k, v) -> map[k]?.let { it to v } }.toMap()
    }
}
