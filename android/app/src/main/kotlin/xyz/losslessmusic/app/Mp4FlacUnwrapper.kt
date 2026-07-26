package xyz.losslessmusic.app

import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFprobeKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import org.json.JSONObject
import xyz.losslessmusic.backend.bridge.Bridge
import java.io.File

/**
 * Finalizes MP4-delivered downloads: decrypts them when the source handed us a
 * key, and unwraps a FLAC stream out of the MP4 container.
 *
 * Amazon's lossless tier streams an **encrypted** MP4 and returns the key in the
 * download result (`decryption: {strategy: "ffmpeg.mov_key", key, input_format:
 * "mov", output_extension: ".flac"}`). go_backend only forwards that — applying
 * it is the app's job, and the extension's own source comments say so ("flac:
 * decrypt to .flac"). Skipping it leaves a file whose *container labels* read as
 * FLAC 24-bit (so the library shows it as hi-res and tagging appears to work)
 * while every audio frame is ciphertext, which no player can decode.
 *
 * `-decryption_key` is only honoured by the MOV/MP4 demuxer, hence `-f mov`.
 * After decryption a plain `-c copy` is correct: the payload is already FLAC.
 */
object Mp4FlacUnwrapper {
    private const val TAG = "Mp4FlacUnwrapper"

    /** Strategy aliases that mean "pass the key to ffmpeg's MOV demuxer". */
    private val MOV_KEY_STRATEGIES = setOf(
        "", "ffmpeg.mov_key", "ffmpeg_mov_key", "mov_decryption_key",
        "mp4_decryption_key", "ffmpeg.mp4_decryption_key",
    )

    fun looksLikeMp4Container(path: String): Boolean {
        if (path.startsWith("content://") || path.startsWith("/proc/self/fd/")) return false
        val lower = path.lowercase()
        return lower.endsWith(".m4a") || lower.endsWith(".mp4")
    }

    /**
     * Returns the path to the finished audio file. Falls back to the untouched
     * input whenever nothing can be improved — a normal AAC/ALAC download is a
     * perfectly good file, and a half-processed one would be worse than none.
     */
    fun finalize(resultJson: String, requestJson: String): String {
        val result = try {
            JSONObject(resultJson)
        } catch (e: Exception) {
            return ""
        }
        val path = result.optString("file_path", "")
        if (path.isEmpty() || !looksLikeMp4Container(path)) return path
        if (!File(path).exists()) return path

        val decrypted = decrypt(path, result, requestJson)
        if (decrypted != null) return decrypted
        return unwrapPlainFlac(path, requestJson)
    }

    /** Decrypts an MP4 whose key the extension supplied. Null when there is none. */
    private fun decrypt(path: String, result: JSONObject, requestJson: String): String? {
        val info = result.optJSONObject("decryption")
        val key = (info?.optString("key") ?: result.optString("decryption_key", "")).trim()
        if (key.isEmpty()) return null

        val strategy = (info?.optString("strategy") ?: "").trim().lowercase()
        if (strategy !in MOV_KEY_STRATEGIES) {
            android.util.Log.w(TAG, "unsupported decryption strategy '$strategy', keeping $path")
            return null
        }

        // The extension picks the container the decrypted stream can legally live
        // in (.flac for FLAC; .mp4 for eac3/ac4/opus, which the flac muxer rejects).
        val ext = (info?.optString("output_extension") ?: result.optString("output_extension", ""))
            .trim()
            .ifEmpty { ".flac" }
            .let { if (it.startsWith(".")) it else ".$it" }
        val out = File(path.substringBeforeLast('.') + ext)
        if (out.absolutePath == path) return null
        if (out.exists()) out.delete()

        val demuxer = (info?.optString("input_format") ?: "").trim().ifEmpty { "mov" }
        val ok = runFfmpeg(
            arrayOf(
                "-y", "-decryption_key", key, "-f", demuxer, "-i", path,
                "-map", "0:a:0", "-c", "copy", out.absolutePath,
            ),
        )
        if (!ok || !out.exists() || out.length() == 0L) {
            if (out.exists()) out.delete()
            android.util.Log.w(TAG, "decryption failed, keeping $path")
            return null
        }

        if (!File(path).delete()) {
            android.util.Log.w(TAG, "could not remove encrypted $path")
        }
        android.util.Log.i(TAG, "decrypted download to ${out.absolutePath}")
        if (ext == ".flac") tagFlacWithRepair(out, requestJson)
        return out.absolutePath
    }

    /**
     * Handles the unencrypted case: a plain FLAC stream sitting in an MP4 box.
     * Probes first, because re-encoding would otherwise happily turn an AAC
     * stream into FLAC and pass off lossy audio as lossless.
     */
    private fun unwrapPlainFlac(path: String, requestJson: String): String {
        if (audioCodecOf(path) != "flac") return path

        val out = File(path.substringBeforeLast('.') + ".flac")
        if (out.exists()) out.delete()
        // FLAC in, FLAC out is bit-identical audio, and unlike a stream copy it
        // rebuilds frame headers that parsers accept.
        val ok = runFfmpeg(
            arrayOf("-y", "-i", path, "-map", "0:a:0", "-c:a", "flac", out.absolutePath),
        )
        if (!ok || !out.exists() || out.length() == 0L) {
            if (out.exists()) out.delete()
            android.util.Log.w(TAG, "FLAC unwrap failed, keeping $path")
            return path
        }
        if (!File(path).delete()) {
            android.util.Log.w(TAG, "could not remove $path after unwrapping")
        }
        android.util.Log.i(TAG, "unwrapped FLAC from MP4 container: ${out.absolutePath}")
        tagFlacWithRepair(out, requestJson)
        return out.absolutePath
    }

    private fun runFfmpeg(args: Array<String>): Boolean = try {
        val session = FFmpegKit.executeWithArguments(args)
        val ok = ReturnCode.isSuccess(session.returnCode)
        if (!ok) {
            android.util.Log.w(TAG, "ffmpeg rc=${session.returnCode}: ${session.allLogsAsString?.takeLast(300)}")
        }
        ok
    } catch (e: Exception) {
        android.util.Log.w(TAG, "ffmpeg threw: ${e.message}")
        false
    }

    /** Codec of the first audio stream, lowercased, or "" when it can't be read. */
    private fun audioCodecOf(path: String): String = try {
        FFprobeKit.getMediaInformation(path).mediaInformation?.streams
            ?.firstOrNull { it.type == "audio" }
            ?.codec
            ?.lowercase()
            .orEmpty()
    } catch (e: Exception) {
        android.util.Log.w(TAG, "probe failed: ${e.message}")
        ""
    }

    /**
     * go_backend skipped its native FLAC tagger for this download (the file was
     * still MP4 at the time), so tag it now. If the parser rejects the stream,
     * re-encode once to rebuild it — the same validate-then-repair order
     * SpotiFLAC's module uses.
     */
    private fun tagFlacWithRepair(file: File, requestJson: String) {
        if (tagFlac(file.absolutePath, requestJson)) return
        if (repair(file)) tagFlac(file.absolutePath, requestJson)
    }

    private fun repair(file: File): Boolean {
        val tmp = File(file.absolutePath + ".repair.flac")
        if (tmp.exists()) tmp.delete()
        val ok = runFfmpeg(
            arrayOf(
                "-y", "-i", file.absolutePath,
                "-c:a", "flac", "-compression_level", "8", tmp.absolutePath,
            ),
        )
        if (!ok || !tmp.exists() || tmp.length() == 0L) {
            if (tmp.exists()) tmp.delete()
            return false
        }
        if (!file.delete() || !tmp.renameTo(file)) {
            tmp.delete()
            android.util.Log.w(TAG, "could not swap in repaired FLAC")
            return false
        }
        android.util.Log.i(TAG, "repaired FLAC: ${file.absolutePath}")
        return true
    }

    /** Best effort: an untagged lossless file still beats a mislabelled one. */
    private fun tagFlac(flacPath: String, requestJson: String): Boolean {
        try {
            val req = JSONObject(requestJson)
            if (!req.optBoolean("embed_metadata", true)) return true
            val md = JSONObject()
            fun copy(from: String, to: String) {
                val v = req.optString(from, "").trim()
                if (v.isNotEmpty()) md.put(to, v)
            }
            copy("track_name", "title")
            copy("artist_name", "artist")
            copy("album_name", "album")
            copy("album_artist", "albumArtist")
            copy("isrc", "isrc")
            copy("genre", "genre")
            val date = req.optString("release_date", "").trim()
            if (date.length >= 4) md.put("year", date.substring(0, 4))
            val track = req.optInt("track_number", 0)
            if (track > 0) md.put("trackNumber", track.toString())
            if (md.length() == 0) return true

            val res = JSONObject(Bridge.editFileMetadata(flacPath, md.toString()))
            val err = res.optString("error", "")
            if (err.isNotEmpty()) {
                android.util.Log.w(TAG, "tagging FLAC failed: $err")
                return false
            }
            return true
        } catch (e: Exception) {
            android.util.Log.w(TAG, "tagging FLAC failed: ${e.message}")
            return false
        }
    }
}
