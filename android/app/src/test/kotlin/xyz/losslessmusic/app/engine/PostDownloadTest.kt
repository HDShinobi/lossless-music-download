package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class PostDownloadTest {
    private val fake = FakeRustCore()
    private val logs = mutableListOf<String>()
    private fun req(embedLyrics: Boolean = true, embedMetadata: Boolean = true) = JSONObject()
        .put("track_name", "One More Time").put("artist_name", "Daft Punk")
        .put("spotify_id", "sp1").put("duration_ms", 320000)
        .put("embed_lyrics", embedLyrics).put("embed_metadata", embedMetadata)
    private fun ok(path: String = "/m/a.flac", extra: JSONObject.() -> Unit = {}) =
        JSONObject().put("success", true).put("file_path", path).apply(extra).toString()
    private fun apply(request: JSONObject, result: String) = PostDownload.apply(fake, request, result) { logs += it }

    @Test fun embedsFetchedLyricsIntoNewFlac() {
        val out = apply(req(), ok())
        assertEquals(listOf("/m/a.flac" to "[00:00.00]x"), fake.embeds)
        assertEquals(ok(), out)
        assertTrue(fake.calls.contains("lyrics:One More Time"))
    }

    @Test fun postDownloadSkipsWhenEngineAlreadyHasLyrics() {
        apply(req(), ok { put("lyrics_lrc", "[00:01.00]from extension") })
        assertTrue(fake.embeds.isEmpty())
        assertTrue(fake.calls.none { it.startsWith("lyrics:") })
    }

    @Test fun instrumentalSentinelAndBlankAreSkipped() {
        fake.lyricsLrc = "[instrumental:true]"; apply(req(), ok())
        fake.lyricsLrc = "   "; apply(req(), ok())
        assertTrue(fake.embeds.isEmpty())
    }

    @Test fun postDownloadOnlyEmbedsNewFlacFiles() {
        apply(req(), ok("/m/a.opus"))
        apply(req(), ok { put("already_exists", true) })
        apply(req(embedLyrics = false), ok())
        apply(req(embedMetadata = false), ok())
        apply(req(), JSONObject().put("success", false).put("error", "x").toString())
        assertTrue(fake.embeds.isEmpty())
    }

    @Test fun postDownloadFailureNeverFailsTheDownload() {
        fake.lyricsThrows = IllegalStateException("lyrics down")
        assertEquals(ok(), apply(req(), ok()))
        assertTrue(logs.any { it.contains("lyrics down") })
        logs.clear()
        fake.lyricsThrows = null; fake.embedThrows = IllegalStateException("embed failed")
        assertEquals(ok(), apply(req(), ok()))
        assertTrue(logs.any { it.contains("embed failed") })
    }

    @Test fun embedFailureInReturnedJsonIsLoggedWithoutFailingDownload() {
        fake.embedResult = "{\"success\":false,\"error\":\"Failed to embed lyrics: disk full\"}"
        assertEquals(ok(), apply(req(), ok()))
        assertTrue(logs.any { it.contains("Failed to embed lyrics: disk full") })
    }

    @Test fun preflightFailureIsReclassifiedAsVerificationRequired() {
        val failed = JSONObject().put("success", false)
            .put("error", "Could not start verification for amazon: network down").put("error_type", "network").toString()
        val out = JSONObject(apply(req(), failed))
        assertEquals("verification_required", out.getString("error_type"))
        assertEquals("Verification required for amazon but could not start it: network down", out.getString("error"))
        // lib/utils/extension_auth_launcher.dart matches the error text, not error_type.
        assertTrue(out.getString("error").lowercase().contains("verification required"))
    }

    @Test fun preflightFailureWithoutProviderSeparatorUsesFallbackMessage() {
        val failed = JSONObject().put("success", false)
            .put("error", "Could not start verification for amazon").put("error_type", "unknown")
            .put("service", "amazon").toString()
        val out = JSONObject(apply(req(), failed))
        assertEquals("verification_required", out.getString("error_type"))
        assertEquals("Verification required but could not start it: Could not start verification for amazon", out.getString("error"))
        assertEquals("amazon", out.getString("service"))
    }

    @Test fun otherFailuresKeepTheirType() {
        val failed = JSONObject().put("success", false).put("error", "rate limited").put("error_type", "rate_limit").toString()
        assertEquals(failed, apply(req(), failed))
    }

    @Test fun preflightPrefixStillExistsInVendoredRust() {
        val src = File("../../rust_backend/crates/extensions/src/backend/downloads.rs").readText()
        assertTrue("upstream reworded the preflight message; update PostDownload.PREFLIGHT_PREFIX", src.contains(PostDownload.PREFLIGHT_PREFIX))
    }
}
