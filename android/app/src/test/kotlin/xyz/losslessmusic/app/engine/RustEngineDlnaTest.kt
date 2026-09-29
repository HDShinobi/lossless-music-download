package xyz.losslessmusic.app.engine

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RustEngineDlnaTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun metadataReadGrantsCanonicalAudioParent() {
        val fake = FakeRustCore()
        val engine = readyEngine(fake)
        val audioDir = tmp.newFolder("audio")
        val path = File(audioDir, "song.flac")
        assertEquals(fake.audioMetadata, engine.readTrackMetadata(path.path))
        assertEquals(listOf("grant:${audioDir.canonicalPath}", "readAudio:${path.canonicalPath}", "release"),
            fake.calls.takeLast(3))
    }

    @Test fun coverExtractionGrantsAudioThenOutputParent() {
        val fake = FakeRustCore()
        val engine = readyEngine(fake)
        val audioDir = tmp.newFolder("audio")
        val outputDir = tmp.newFolder("covers")
        val audio = File(audioDir, "song.flac")
        val output = File(outputDir, "cover.img")
        engine.extractCoverToFile(audio.path, output.path)
        assertEquals(listOf("grant:${audioDir.canonicalPath}", "grant:${outputDir.canonicalPath}",
            "extractCover:${audio.canonicalPath}:${output.canonicalPath}", "release", "release"), fake.calls.takeLast(5))
    }

    private fun readyEngine(fake: FakeRustCore): RustEngine {
        val files = tmp.newFolder("files")
        val ext = File(files, "extensions").apply { mkdirs() }
        val data = File(files, "ext_data").apply { mkdirs() }
        return RustEngine({ _, _, _, _ -> fake }, files, readyTimeoutMs = 100).also {
            it.setExtensionStorageMasterKey("KEY")
            it.initExtensionSystem(ext.path, data.path)
        }
    }
}
