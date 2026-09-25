package xyz.losslessmusic.app.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class EngineDataIsolationTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun goDirs(): Pair<File, File> {
        val support = tmp.newFolder("support")
        val ext = File(support, "extensions").apply { mkdirs() }
        val data = File(support, "ext_data").apply { mkdirs() }
        File(ext, "qobuz/manifest.json").apply { parentFile.mkdirs(); writeText("{\"id\":\"qobuz\"}") }
        File(data, "qobuz/storage.enc").apply { parentFile.mkdirs(); writeBytes(byteArrayOf(1, 2, 3)) }
        return ext to data
    }

    private fun snapshot(dir: File): Map<String, String> =
        dir.walkTopDown().filter { it.isFile }.associate { it.relativeTo(dir).path to it.readBytes().contentToString() }

    @Test fun copiesGoDataIntoEngineRustAndLeavesSourceUntouched() {
        val (ext, data) = goDirs()
        val before = snapshot(ext.parentFile)
        val dirs = EngineDataIsolation.ensureRustCopy(ext, data)
        assertEquals(File(ext.parentFile, "engine-rust/extensions"), dirs.extensions)
        assertEquals(File(ext.parentFile, "engine-rust/ext_data"), dirs.data)
        assertEquals("{\"id\":\"qobuz\"}", File(dirs.extensions, "qobuz/manifest.json").readText())
        assertTrue(File(dirs.data, "qobuz/storage.enc").readBytes().contentEquals(byteArrayOf(1, 2, 3)))
        assertEquals(before, snapshot(ext.parentFile).filterKeys { !it.startsWith("engine-rust") })
    }

    @Test fun secondCallReusesExistingCopy() {
        val (ext, data) = goDirs()
        val dirs = EngineDataIsolation.ensureRustCopy(ext, data)
        File(dirs.data, "qobuz/storage.enc").writeBytes(byteArrayOf(9))      // Rust wrote its copy
        File(ext, "qobuz/manifest.json").writeText("{\"id\":\"changed-by-go\"}") // Go wrote its dir
        EngineDataIsolation.ensureRustCopy(ext, data)
        assertTrue(File(dirs.data, "qobuz/storage.enc").readBytes().contentEquals(byteArrayOf(9)))
        assertEquals("{\"id\":\"qobuz\"}", File(dirs.extensions, "qobuz/manifest.json").readText())
    }

    @Test fun writesToCopyNeverReachGoDirs() {
        val (ext, data) = goDirs()
        val dirs = EngineDataIsolation.ensureRustCopy(ext, data)
        File(dirs.extensions, "new-ext/manifest.json").apply { parentFile.mkdirs(); writeText("x") }
        assertFalse(File(ext, "new-ext").exists())
    }

    @Test fun missingGoDirsProduceEmptyCopy() {
        val support = tmp.newFolder("fresh")
        val dirs = EngineDataIsolation.ensureRustCopy(File(support, "extensions"), File(support, "ext_data"))
        assertTrue(dirs.extensions.isDirectory && dirs.extensions.list()!!.isEmpty())
        assertTrue(dirs.data.isDirectory && dirs.data.list()!!.isEmpty())
        assertFalse(File(support, "extensions").exists())
    }

    @Test fun staleTempFromInterruptedCopyIsDiscarded() {
        val (ext, data) = goDirs()
        val stale = File(ext.parentFile, "engine-rust.tmp-dead").apply { mkdirs() }
        File(stale, "extensions/half").apply { parentFile.mkdirs(); writeText("partial") }
        val dirs = EngineDataIsolation.ensureRustCopy(ext, data)
        assertFalse(stale.exists())
        assertFalse(File(dirs.extensions, "half").exists())
        assertTrue(File(dirs.extensions, "qobuz/manifest.json").exists())
    }

    @Test fun engineVersionIsTheVendoredBaseline() {
        assertEquals("5.0.0", EngineVersion.SPOTIFLAC_ENGINE_VERSION)
    }
}
