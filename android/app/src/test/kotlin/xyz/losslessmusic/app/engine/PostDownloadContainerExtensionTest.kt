package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class PostDownloadContainerExtensionTest {
    @get:Rule val temp = TemporaryFolder()

    @Test fun mp4PayloadIsRenamedBeforeFlacLyricsFallback() {
        val source = temp.newFile("Beyond.flac")
        source.writeBytes(byteArrayOf(0, 0, 0, 12, 102, 116, 121, 112, 77, 52, 65, 32))
        val core = FakeRustCore()
        val request = JSONObject().put("embed_lyrics", true).put("embed_metadata", true)
            .put("spotify_id", "song").put("track_name", "Beyond")
        val result = JSONObject().put("success", true).put("file_path", source.path)

        val out = JSONObject(PostDownload.apply(core, request, result.toString()) { })

        assertEquals("Beyond.m4a", File(out.getString("file_path")).name)
        assertTrue(File(out.getString("file_path")).exists())
        assertFalse(source.exists())
        assertTrue(core.calls.none { it.startsWith("lyrics:") || it.startsWith("embedLyrics:") })
        assertTrue(core.embeds.isEmpty())
    }

    @Test fun unchangedSuccessRetainsOriginalJsonBytes() {
        val original = "{  \"file_path\" : \"/missing.m4a\", \"success\" : true }"
        val out = PostDownload.apply(FakeRustCore(), JSONObject(), original) { }
        assertEquals(original, out)
    }
}
