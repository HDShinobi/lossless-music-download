package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class ContainerExtensionFixTest {
    @get:Rule val temp = TemporaryFolder()
    private val logs = mutableListOf<String>()

    private fun file(name: String, vararg bytes: Int): File = temp.newFile(name).apply {
        writeBytes(bytes.map { it.toByte() }.toByteArray())
    }

    private fun result(path: String) = JSONObject().put("success", true).put("file_path", path)
    private fun apply(result: JSONObject) = ContainerExtensionFix.apply(result) { logs += it }
    private val mp4 = intArrayOf(0, 0, 0, 12, 102, 116, 121, 112, 77, 52, 65, 32)

    @Test fun mp4HeaderRenamesToM4aAndUpdatesPresentFields() {
        val source = file("Beyond.flac", *mp4)
        val out = apply(result(source.path).put("actual_extension", ".flac")
            .put("output_extension", ".flac").put("resolved_file_name", "Beyond.flac"))
        assertEquals(File(temp.root, "Beyond.m4a").path, out.getString("file_path"))
        assertEquals(".m4a", out.getString("actual_extension"))
        assertEquals(".m4a", out.getString("output_extension"))
        assertEquals("Beyond.m4a", out.getString("resolved_file_name"))
        assertFalse(source.exists())
        assertTrue(File(out.getString("file_path")).exists())
        assertEquals(1, logs.size)
    }

    @Test fun ac4InMp4UsesMp4Extension() {
        val source = file("Beyond.flac", *mp4)
        val out = apply(result(source.path).put("audio_codec", "ac-4"))
        assertEquals("Beyond.mp4", File(out.getString("file_path")).name)
    }

    @Test fun ac4AliasUsesMp4Extension() {
        val source = file("Beyond.flac", *mp4)
        val out = apply(result(source.path).put("audio_codec", "ac4"))
        assertEquals("Beyond.mp4", File(out.getString("file_path")).name)
    }

    @Test fun oggHeaderUsesOpusExtension() {
        val source = file("Beyond.flac", 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0)
        assertEquals("Beyond.opus", File(apply(result(source.path)).getString("file_path")).name)
    }

    @Test fun id3HeaderUsesMp3Extension() {
        val source = file("Beyond.flac", 73, 68, 51, 4, 0, 0, 0, 0, 0, 0, 0, 0)
        assertEquals("Beyond.mp3", File(apply(result(source.path)).getString("file_path")).name)
    }

    @Test fun id3PrefixedFlacWithFooterKeepsFlacExtension() {
        val source = file("Beyond.flac", 73, 68, 51, 4, 0, 0x10, 0, 0, 0, 3,
            1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            102, 76, 97, 67)
        val input = result(source.path)
        assertSame(input, apply(input))
        assertTrue(source.exists())
        assertTrue(logs.isEmpty())
    }

    @Test fun id3PrefixedMpegFrameUsesMp3Extension() {
        val source = file("Beyond.flac", 73, 68, 51, 4, 0, 0, 0, 0, 0, 2,
            1, 2, 255, 251, 0, 0)
        assertEquals("Beyond.mp3", File(apply(result(source.path)).getString("file_path")).name)
    }

    @Test fun mpegFrameSyncUsesMp3Extension() {
        val source = file("Beyond.flac", 255, 251, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        assertEquals("Beyond.mp3", File(apply(result(source.path)).getString("file_path")).name)
    }

    @Test fun adtsFrameUsesAacExtension() {
        val source = file("Beyond.flac", 255, 241, 80, 128)
        assertEquals("Beyond.aac", File(apply(result(source.path)).getString("file_path")).name)
    }

    @Test fun realFlacIsUntouched() {
        val source = file("Beyond.flac", 102, 76, 97, 67, 0, 0, 0, 0, 0, 0, 0, 0)
        val input = result(source.path)
        assertSame(input, apply(input))
        assertTrue(source.exists())
        assertTrue(logs.isEmpty())
    }

    @Test fun existingTargetsArePreservedAndNextUniqueNameIsUsed() {
        val source = file("Beyond.flac", *mp4)
        val first = file("Beyond.m4a", 1)
        val second = file("Beyond (2).m4a", 2)
        val out = apply(result(source.path).put("resolved_file_name", "Beyond.flac"))
        assertEquals("Beyond (3).m4a", File(out.getString("file_path")).name)
        assertEquals("Beyond (3).m4a", out.getString("resolved_file_name"))
        assertArrayEquals(byteArrayOf(1), first.readBytes())
        assertArrayEquals(byteArrayOf(2), second.readBytes())
    }

    @Test fun alreadyExistsResultIsUntouched() {
        val source = file("Beyond.flac", *mp4)
        val input = result(source.path).put("already_exists", true)
        assertSame(input, apply(input))
        assertTrue(source.exists())
    }

    @Test fun nonFlacPathIsUntouched() {
        val source = file("Beyond.m4a", *mp4)
        val input = result(source.path)
        assertSame(input, apply(input))
        assertTrue(source.exists())
    }

    @Test fun missingFileIsUntouched() {
        val input = result(File(temp.root, "missing.flac").path)
        assertSame(input, apply(input))
    }

    @Test fun unknownHeaderIsUntouched() {
        val source = file("Beyond.flac", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
        val input = result(source.path)
        assertSame(input, apply(input))
        assertTrue(source.exists())
    }
}
