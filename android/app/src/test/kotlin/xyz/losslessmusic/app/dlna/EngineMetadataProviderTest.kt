package xyz.losslessmusic.app.dlna

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class EngineMetadataProviderTest {
    @Test fun mapsScanKeysAndRejectsInvalidJson() {
        val dir = Files.createTempDirectory("dlna-tags").toFile()
        try {
            val provider = EngineMetadataProvider({ """{"trackName":"Song","artistName":"Artist","albumName":"Album","albumArtist":"Various","genre":"Jazz","trackNumber":3,"duration":123,"sampleRate":96000,"bitDepth":24,"bitrate":1411}""" }, { _, _ -> }, dir)
            assertEquals(TrackTags("Song", "Artist", "Album", "Various", "Jazz", 3, 123, 96000, 24, 1411), provider.readTags("/song.flac"))
            assertNull(EngineMetadataProvider({ "{" }, { _, _ -> }, dir).readTags("/song.flac"))
            assertNull(EngineMetadataProvider({ "  " }, { _, _ -> }, dir).readTags("/song.flac"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun cachesCoverByPathAndMtimeAndDetectsMime() {
        val dir = Files.createTempDirectory("dlna-cover").toFile()
        val song = File(dir, "song.flac").apply { writeText("audio") }
        var calls = 0
        var bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte())
        val provider = EngineMetadataProvider({ "{}" }, { _, out -> calls++; File(out).writeBytes(bytes) }, File(dir, "art"))
        try {
            assertEquals("image/jpeg", provider.readCover(song.path)?.second)
            assertEquals("image/jpeg", provider.readCover(song.path)?.second)
            assertEquals(1, calls)
            song.setLastModified(song.lastModified() + 2000)
            bytes = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47)
            assertEquals("image/png", provider.readCover(song.path)?.second)
            assertEquals(2, calls)
        } finally { dir.deleteRecursively() }
    }

    @Test fun webpAndMissingCover() {
        val dir = Files.createTempDirectory("dlna-cover").toFile()
        try {
            val webp = EngineMetadataProvider({ "{}" }, { _, out -> File(out).writeBytes("RIFF1234WEBP".toByteArray()) }, dir)
            assertEquals("image/webp", webp.readCover("/webp.flac")?.second)
            val missing = EngineMetadataProvider({ "{}" }, { _, _ -> }, File(dir, "missing"))
            assertNull(missing.readCover("/none.flac"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun missingCoverIsCachedUntilMtimeChanges() {
        val dir = Files.createTempDirectory("dlna-miss").toFile()
        val song = File(dir, "song.flac").apply { writeText("audio") }
        var calls = 0
        val provider = EngineMetadataProvider({ "{}" }, { _, _ -> calls++ }, File(dir, "art"))
        try {
            assertNull(provider.readCover(song.path))
            assertNull(provider.readCover(song.path))
            assertEquals(1, calls)
            song.setLastModified(song.lastModified() + 2000)
            assertNull(provider.readCover(song.path))
            assertEquals(2, calls)
        } finally { dir.deleteRecursively() }
    }

    @Test fun extractionFailureIsCachedUntilMtimeChanges() {
        val dir = Files.createTempDirectory("dlna-miss").toFile()
        val song = File(dir, "song.flac").apply { writeText("audio") }
        var calls = 0
        val provider = EngineMetadataProvider({ "{}" }, { _, _ -> calls++; throw IllegalStateException("no art") }, File(dir, "art"))
        try {
            assertNull(provider.readCover(song.path))
            assertNull(provider.readCover(song.path))
            assertEquals(1, calls)
            song.setLastModified(song.lastModified() + 2000)
            assertNull(provider.readCover(song.path))
            assertEquals(2, calls)
        } finally { dir.deleteRecursively() }
    }
}
