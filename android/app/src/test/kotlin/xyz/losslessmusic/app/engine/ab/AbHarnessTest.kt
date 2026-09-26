package xyz.losslessmusic.app.engine.ab

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import xyz.losslessmusic.app.engine.EngineKind
import xyz.losslessmusic.app.engine.NativeEngine
import java.io.File
import java.lang.reflect.Proxy

class AbHarnessTest {
    @get:Rule val tmp = TemporaryFolder()

    /** A NativeEngine whose every String method returns [answer(method)]; Unit methods do nothing. */
    private fun engine(kind: EngineKind, answer: (String) -> String): NativeEngine =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(NativeEngine::class.java)) { _, m, _ ->
            when {
                m.name == "getKind" -> kind
                m.returnType == String::class.java -> answer(m.name)
                else -> null
            }
        } as NativeEngine

    @Test fun captureThenRestoreResetsGoDirsAndDropsEngineRust() {
        val files = tmp.newFolder("files")
        File(files, "extensions/qobuz/manifest.json").apply { parentFile.mkdirs(); writeText("v1") }
        File(files, "ext_data/x").apply { parentFile.mkdirs(); writeText("d1") }
        File(files, AbHarness.CAPTURE_FLAG).createNewFile()
        AbHarness.onProcessStart(files) {}
        assertFalse(File(files, AbHarness.CAPTURE_FLAG).exists())
        File(files, "extensions/qobuz/manifest.json").writeText("changed")
        File(files, "engine-rust/extensions").mkdirs()
        File(files, AbHarness.RESTORE_FLAG).createNewFile()
        AbHarness.onProcessStart(files) {}
        assertEquals("v1", File(files, "extensions/qobuz/manifest.json").readText())
        assertFalse(File(files, "engine-rust").exists())
        assertFalse(File(files, AbHarness.RESTORE_FLAG).exists())
    }

    @Test fun recordCapturesValuesAndErrors() {
        val music = tmp.newFolder("music")
        val e = engine(EngineKind.GO) { m ->
            if (m == "handleUrl") throw IllegalStateException("no handler") else when (m) {
                "getInstalledExtensions" -> "[{\"id\":\"qobuz-web\"}]"
                "getAllDownloadProgress" -> "{\"items\":{}}"
                else -> "[]"
            }
        }
        val r = AbHarness.record(e, music)
        assertTrue(r.getJSONObject("getInstalledExtensions").getBoolean("ok"))
        assertFalse(r.getJSONObject("handleUrl").getBoolean("ok"))
        assertFalse(r.getJSONObject("getAudioQuality").getBoolean("ok")) // no flac in music dir
    }

    @Test fun recordIfRequestedWritesPerEngineFileAndClearsFlag() {
        val files = tmp.newFolder("files")
        File(files, AbHarness.RECORD_FLAG).createNewFile()
        assertTrue(AbHarness.recordIfRequested(files, tmp.newFolder("m"), engine(EngineKind.RUST) { "[]" }))
        assertTrue(File(files, "ab-rust.json").exists())
        assertFalse(File(files, AbHarness.RECORD_FLAG).exists())
        assertFalse(AbHarness.recordIfRequested(files, tmp.root, engine(EngineKind.RUST) { "[]" }))
    }

    @Test fun compareClassifiesSteps() {
        val go = JSONObject("{\"a\":{\"ok\":true,\"value\":{\"x\":1}},\"b\":{\"ok\":true,\"value\":[1]},\"c\":{\"ok\":false,\"error\":\"e\"}}")
        val rust = JSONObject("{\"a\":{\"ok\":true,\"value\":{\"x\":2}},\"b\":{\"ok\":true,\"value\":[\"s\"]},\"c\":{\"ok\":true,\"value\":1}}")
        val d = AbHarness.compare(go, rust)
        assertEquals("same", d.getJSONObject("a").getString("status"))
        assertEquals("differs", d.getJSONObject("b").getString("status"))
        assertEquals("go_error", d.getJSONObject("c").getString("status"))
        assertEquals(1, d.getJSONObject("_summary").getInt("same"))
    }
}
