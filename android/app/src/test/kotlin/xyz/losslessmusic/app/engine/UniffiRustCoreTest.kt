package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

class UniffiRustCoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private val key = Base64.getEncoder().encodeToString(ByteArray(32) { it.toByte() })
    private lateinit var core: RustCore
    private lateinit var out: File

    @Before fun setUp() {
        val src = tmp.newFolder("extensions")
        val data = tmp.newFolder("ext_data")
        out = tmp.newFolder("downloads")
        core = UniffiRustCore.FACTORY.create(src.canonicalPath, data.canonicalPath, key, "5.0.0")
        core.setAllowedDownloadDirectories(listOf(out.canonicalPath, out.absolutePath))
    }

    @After fun tearDown() { core.close() }

    @Test fun freshEngineHasNoExtensionsAndEmptyPriorities() {
        assertEquals(0, JSONArray(core.installed()).length())
        val p = JSONObject(core.providerPriorities())
        assertEquals(0, p.getJSONArray("download").length())
        assertEquals(0, p.getJSONArray("metadata").length())
    }

    @Test fun progressIsAnItemsObject() {
        assertTrue(JSONObject(core.allProgress()).has("items"))
    }

    @Test fun readAudioMetadataReportsQuality() {
        val flac = File(out, "silence.flac")
        File("../../go_backend/testdata/silence.flac").copyTo(flac)
        val scope = core.grantDownloadDirectories(listOf(out.canonicalPath))
        try {
            val m = JSONObject(core.readAudioMetadata(flac.canonicalPath))
            assertTrue(m.toString(), m.optInt("sampleRate") > 0)
        } finally {
            scope.close()
        }
    }

    @Test fun isrcLookupOnEmptyDirIsEmptyString() {
        assertEquals("", core.checkIsrcExists(out.canonicalPath, "USUM71703861"))
    }

    @Test fun downloadThroughPumpReturnsInBandFailureWhenExtensionsDisabled() {
        val req = JSONObject()
            .put("item_id", "t1").put("output_dir", out.canonicalPath)
            .put("use_extensions", false).put("track_name", "x").put("artist_name", "y")
        val res = JSONObject(core.downloadWithPump(req.toString()))
        assertFalse(res.getBoolean("success"))
        assertTrue(res.optString("error").isNotBlank())
    }

    @Test fun unknownCallbackStateThrows() {
        var threw = false
        try { core.resolveCallbackState("no-such-state") } catch (e: Exception) { threw = true }
        assertTrue(threw)
    }
}
