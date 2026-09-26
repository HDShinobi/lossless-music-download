package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject

/** Pure JSON adapters between Rust engine shapes and the Go-era shapes Dart reads. */
object RustJson {
    const val EMPTY_PROGRESS = "{\"items\":{}}"

    fun ids(json: String): List<String> {
        val array = JSONArray(json)
        return List(array.length()) { array.getString(it) }
    }

    fun idsOrNull(json: String?): List<String>? {
        val trimmed = json?.trim() ?: return null
        if (trimmed.isEmpty() || trimmed == "null") return null
        return ids(trimmed)
    }

    fun priorities(raw: String, kind: String): String =
        JSONObject(raw).optJSONArray(kind)?.toString() ?: "[]"

    fun duplicate(path: String): String =
        JSONObject().put("exists", path.isNotEmpty()).put("filepath", path).toString()

    fun audioQuality(raw: String): String {
        val m = JSONObject(raw)
        val out = JSONObject()
            .put("bit_depth", m.optInt("bitDepth", 0))
            .put("sample_rate", m.optInt("sampleRate", 0))
            .put("total_samples", 0)
            .put("duration", m.optInt("duration", 0))
        if (m.has("bitrate")) out.put("bitrate", m.optInt("bitrate"))
        val format = m.optString("format", "")
        if (format.isNotEmpty()) out.put("codec", format)
        return out.toString()
    }
}
