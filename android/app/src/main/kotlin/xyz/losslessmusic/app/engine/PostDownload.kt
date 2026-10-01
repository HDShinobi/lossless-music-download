package xyz.losslessmusic.app.engine

import org.json.JSONObject

/**
 * Our post-download step on the Rust path (spec §5): fix 1 (lyrics fallback embed, preserving
 * the previous engine behavior) and fix 4 (preflight verification failure reclassified).
 * Never fails a download: every error is logged and the engine's result is returned.
 */
object PostDownload {
    const val INSTRUMENTAL = "[instrumental:true]"
    const val PREFLIGHT_PREFIX = "Could not start verification for"

    fun apply(core: RustCore, request: JSONObject, result: String, log: (String) -> Unit): String {
        val r = try { JSONObject(result) } catch (e: Exception) { return result }
        if (!r.optBoolean("success", false)) return reclassify(r, result)
        val originalPath = r.optString("file_path", "")
        ContainerExtensionFix.apply(r, log)
        embedLyricsIfNeeded(core, request, r, log)
        return if (r.optString("file_path", "") == originalPath) result else r.toString()
    }

    private fun reclassify(r: JSONObject, original: String): String {
        val error = r.optString("error", "")
        if (!error.startsWith(PREFLIGHT_PREFIX)) return original
        val providerStart = "$PREFLIGHT_PREFIX "
        val separator = if (error.startsWith(providerStart)) error.indexOf(": ", providerStart.length) else -1
        val message = if (separator >= 0) {
            val provider = error.substring(providerStart.length, separator)
            val cause = error.substring(separator + 2)
            "Verification required for $provider but could not start it: $cause"
        } else {
            "Verification required but could not start it: $error"
        }
        return r.put("error", message).put("error_type", "verification_required").toString()
    }

    private fun embedLyricsIfNeeded(core: RustCore, request: JSONObject, r: JSONObject, log: (String) -> Unit) {
        if (!request.optBoolean("embed_lyrics", false) || !request.optBoolean("embed_metadata", false)) return
        if (r.optBoolean("already_exists", false)) return
        val path = r.optString("file_path", "")
        if (!path.lowercase().endsWith(".flac")) return
        if (r.optString("lyrics_lrc", "").isNotBlank()) return
        try {
            val lrc = core.getLyricsLrc(
                request.optString("spotify_id", ""),
                request.optString("track_name", ""),
                request.optString("artist_name", ""),
                "",
                request.optLong("duration_ms", 0L),
            ).trim()
            if (lrc.isEmpty() || lrc == INSTRUMENTAL) return
            val embedResult = core.embedLyricsToFile(path, lrc)
            val embed = try { JSONObject(embedResult) } catch (_: Exception) { null }
            if (embed?.optBoolean("success", true) == false) {
                log("post-download lyrics: ${embed.optString("error", "unknown embed error")}")
            }
        } catch (e: Exception) {
            log("post-download lyrics: ${e.message}")
        }
    }
}
