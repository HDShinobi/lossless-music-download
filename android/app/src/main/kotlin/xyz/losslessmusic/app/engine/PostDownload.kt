package xyz.losslessmusic.app.engine

import org.json.JSONObject

/**
 * Our post-download step on the Rust path (spec §5): fix 1 (lyrics fallback embed, parity with
 * go_backend/embed_after_download.go) and fix 4 (preflight verification failure reclassified).
 * Never fails a download: every error is logged and the engine's result is returned.
 */
object PostDownload {
    const val INSTRUMENTAL = "[instrumental:true]"
    const val PREFLIGHT_PREFIX = "Could not start verification for"

    fun apply(core: RustCore, request: JSONObject, result: String, log: (String) -> Unit): String {
        val r = try { JSONObject(result) } catch (e: Exception) { return result }
        if (!r.optBoolean("success", false)) return reclassify(r, result)
        embedLyricsIfNeeded(core, request, r, log)
        return result
    }

    private fun reclassify(r: JSONObject, original: String): String {
        val error = r.optString("error", "")
        if (!error.startsWith(PREFLIGHT_PREFIX)) return original
        return r.put("error_type", "verification_required").toString()
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
            core.embedLyricsToFile(path, lrc)
        } catch (e: Exception) {
            log("post-download lyrics: ${e.message}")
        }
    }
}
