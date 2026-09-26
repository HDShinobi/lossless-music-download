package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RustJsonTest {
    @Test fun idsParsesAnArray() = assertEquals(listOf("a", "b"), RustJson.ids("[\"a\",\"b\"]"))

    @Test(expected = Exception::class) fun idsRejectsMalformedJson() { RustJson.ids("not json") }

    @Test fun idsOrNullTreatsBlankAndNullAsClear() {
        assertNull(RustJson.idsOrNull(null)); assertNull(RustJson.idsOrNull("")); assertNull(RustJson.idsOrNull(" null "))
        assertEquals(listOf("x"), RustJson.idsOrNull("[\"x\"]"))
    }

    @Test fun prioritiesUnwrapsTheRequestedKind() {
        val raw = "{\"download\":[\"qobuz-web\",\"amazon\"],\"metadata\":[\"deezer\"]}"
        assertEquals(listOf("qobuz-web", "amazon"), RustJson.ids(RustJson.priorities(raw, "download")))
        assertEquals(listOf("deezer"), RustJson.ids(RustJson.priorities(raw, "metadata")))
        assertEquals("[]", RustJson.priorities("{}", "download"))
    }

    @Test fun duplicateKeepsTheGoKeyNames() {
        val hit = JSONObject(RustJson.duplicate("/m/a.flac"))
        assertTrue(hit.getBoolean("exists")); assertEquals("/m/a.flac", hit.getString("filepath"))
        val miss = JSONObject(RustJson.duplicate(""))
        assertFalse(miss.getBoolean("exists")); assertEquals("", miss.getString("filepath"))
    }

    @Test fun audioQualityMapsCamelCaseToGoShape() {
        val q = JSONObject(RustJson.audioQuality("{\"bitDepth\":24,\"sampleRate\":96000,\"duration\":245,\"bitrate\":2300,\"format\":\"flac\"}"))
        assertEquals(24, q.getInt("bit_depth")); assertEquals(96000, q.getInt("sample_rate"))
        assertEquals(245, q.getInt("duration")); assertEquals(2300, q.getInt("bitrate"))
        assertEquals("flac", q.getString("codec")); assertEquals(0, q.getInt("total_samples"))
    }

    @Test fun audioQualityOmitsAbsentOptionalFields() {
        val q = JSONObject(RustJson.audioQuality("{\"sampleRate\":44100}"))
        assertEquals(0, q.getInt("bit_depth")); assertFalse(q.has("bitrate")); assertFalse(q.has("codec"))
    }

    @Test fun emptyProgressIsAnEmptyItemsObject() =
        assertEquals(0, JSONObject(RustJson.EMPTY_PROGRESS).getJSONObject("items").length())
}
