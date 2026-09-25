package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

class RustEngineProbeTest {
    @get:Rule val tmp = TemporaryFolder()
    private val key = Base64.getEncoder().encodeToString(ByteArray(32) { it.toByte() })

    private fun support(): Pair<File, File> {
        val s = tmp.newFolder("support")
        return File(s, "extensions") to File(s, "ext_data")
    }

    @Test fun freshProfileReportsEmptyInstallList() {
        val (ext, data) = support()
        val result = RustEngineProbe.run(ext, data, key)
        assertTrue(result.toString(), result.getBoolean("ok"))
        assertEquals("5.0.0", result.getString("engine_version"))
        assertEquals(0, JSONArray(result.getString("installed")).length())
        assertFalse("Go dir must not be created", ext.exists())
    }

    @Test fun invalidMasterKeyIsReportedNotThrown() {
        val (ext, data) = support()
        val result = RustEngineProbe.run(ext, data, "not-a-valid-key")
        assertFalse(result.getBoolean("ok"))
        assertTrue(result.getString("error").isNotBlank())
    }

    @Test fun runIfRequestedOnlyRunsWithFlagAndWritesResult() {
        val (ext, data) = support()
        val files = tmp.newFolder("files")
        assertFalse(RustEngineProbe.runIfRequested(files, ext, data, key))
        assertFalse(File(files, RustEngineProbe.RESULT_FILE).exists())

        File(files, RustEngineProbe.FLAG_FILE).createNewFile()
        assertTrue(RustEngineProbe.runIfRequested(files, ext, data, key))
        val written = JSONObject(File(files, RustEngineProbe.RESULT_FILE).readText())
        assertTrue(written.getBoolean("ok"))
    }
}
