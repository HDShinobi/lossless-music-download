package xyz.losslessmusic.app

import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class OutputPostProcessorTest {
    @Test fun sameCanonicalPathWaitsButOtherPathsCanProceed() = runBlocking {
        val dir = Files.createTempDirectory("postprocess").toFile()
        val processor = OutputPostProcessor()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val path = dir.resolve("song.m4a").path
        fun result(path: String) = JSONObject().put("file_path", path)
        val first = launch {
            processor.run(result(path)) {
                entered.complete(Unit)
                release.await()
                path
            }
        }
        try {
            entered.await()
            var secondEntered = false
            val second = async(start = CoroutineStart.UNDISPATCHED) {
                processor.run(result(dir.resolve("./song.m4a").path)) {
                    secondEntered = true
                    path
                }
            }
            assertFalse(secondEntered)
            withTimeout(2000) {
                processor.run(result(dir.resolve("other.m4a").path)) { "other" }
            }
            release.complete(Unit)
            first.join()
            second.await()
            assertTrue(secondEntered)
        } finally {
            release.complete(Unit)
            first.cancelAndJoin()
            dir.deleteRecursively()
        }
    }

    @Test fun existingOutputSkipsEveryPostProcessingStep() = runBlocking {
        val result = JSONObject().put("file_path", "/music/song.m4a")
            .put("already_exists", true)
        val path = OutputPostProcessor().run(result) { error("must not finalize duplicate") }
        assertEquals("/music/song.m4a", path)
    }

    @Test fun lockIsReleasedAfterFailure() = runBlocking {
        val processor = OutputPostProcessor()
        val result = JSONObject().put("file_path", "/music/song.m4a")
        try { processor.run(result) { error("tag failed") } }
        catch (_: IllegalStateException) { }
        assertEquals("done", withTimeout(2000) { processor.run(result) { "done" } })
    }

    @Test fun failedReplacementPreservesOriginalAudio() {
        val dir = Files.createTempDirectory("embed-replace").toFile()
        try {
            val original = dir.resolve("song.m4a").apply { writeText("old audio") }
            try {
                NonFlacMetadataEmbedder.replaceOutput(dir.resolve("missing.m4a"), original)
                fail("missing temp must fail")
            } catch (_: java.io.IOException) { }
            assertEquals("old audio", original.readText())
        } finally { dir.deleteRecursively() }
    }

    @Test fun completedTempReplacesExistingAudio() {
        val dir = Files.createTempDirectory("embed-replace").toFile()
        try {
            val original = dir.resolve("song.m4a").apply { writeText("old audio") }
            val temp = dir.resolve("temp.m4a").apply { writeText("tagged audio") }
            NonFlacMetadataEmbedder.replaceOutput(temp, original)
            assertEquals("tagged audio", original.readText())
            assertFalse(temp.exists())
        } finally { dir.deleteRecursively() }
    }
}
