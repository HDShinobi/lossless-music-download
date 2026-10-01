package xyz.losslessmusic.app.dlna

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
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
    @Test fun differentPathsDoNotWaitForEachOthersExtraction() {
        val dir = Files.createTempDirectory("dlna-parallel").toFile()
        val enteredA = CountDownLatch(1)
        val releaseA = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        val bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte())
        val provider = EngineMetadataProvider({ "{}" }, { path, out ->
            if (path == "/a.flac") {
                enteredA.countDown()
                check(releaseA.await(2, TimeUnit.SECONDS))
            }
            File(out).writeBytes(bytes)
        }, dir)
        try {
            val a = pool.submit<Pair<ByteArray, String>?> { provider.readCover("/a.flac") }
            assertTrue(enteredA.await(1, TimeUnit.SECONDS))
            val b = pool.submit<Pair<ByteArray, String>?> { provider.readCover("/b.flac") }
            assertArrayEquals(bytes, b.get(1, TimeUnit.SECONDS)?.first)
            assertFalse(a.isDone)
            releaseA.countDown()
            assertArrayEquals(bytes, a.get(1, TimeUnit.SECONDS)?.first)
        } finally {
            releaseA.countDown()
            pool.shutdownNow()
            assertTrue(pool.awaitTermination(2, TimeUnit.SECONDS))
            dir.deleteRecursively()
        }
    }
    @Test fun existingThumbnailSkipsExtractionAndThumbnailing() {
        val dir = Files.createTempDirectory("dlna-thumb-hit").toFile()
        val bytes = byteArrayOf(10, 20, 30)
        val thumb = File(dir, cacheKey("/cached.flac") + "-t600.jpg").apply { writeBytes(bytes) }
        val provider = EngineMetadataProvider({ "{}" }, { _, _ -> fail("cache hit extracted") }, dir,
            thumbnail = { _, _, _ -> fail("cache hit thumbnailed"); false })
        try {
            val cover = provider.readCover("/cached.flac")!!
            assertArrayEquals(bytes, cover.first)
            assertEquals("image/jpeg", cover.second)
            assertTrue(thumb.isFile)
        } finally { dir.deleteRecursively() }
    }

    @Test fun eightReadersExtractAndThumbnailSamePathOnce() {
        val dir = Files.createTempDirectory("dlna-thumb-concurrent").toFile()
        val pool = Executors.newFixedThreadPool(8)
        val ready = CountDownLatch(8)
        val start = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val extractions = AtomicInteger()
        val thumbnails = AtomicInteger()
        val original = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47)
        val bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 42)
        val provider = EngineMetadataProvider({ "{}" }, { _, out ->
            extractions.incrementAndGet()
            entered.countDown()
            check(release.await(2, TimeUnit.SECONDS))
            File(out).writeBytes(original)
        }, dir, thumbnail = { src, dst, maxPx ->
            thumbnails.incrementAndGet()
            assertArrayEquals(original, src.readBytes())
            assertEquals(600, maxPx)
            dst.writeBytes(bytes)
            true
        })
        try {
            val results = (1..8).map {
                pool.submit<Pair<ByteArray, String>?> {
                    ready.countDown()
                    check(start.await(2, TimeUnit.SECONDS))
                    provider.readCover("/same.flac")
                }
            }
            assertTrue(ready.await(1, TimeUnit.SECONDS))
            start.countDown()
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            release.countDown()
            results.forEach {
                val cover = it.get(2, TimeUnit.SECONDS)!!
                assertArrayEquals(bytes, cover.first)
                assertEquals("image/jpeg", cover.second)
            }
            assertEquals(1, extractions.get())
            assertEquals(1, thumbnails.get())
        } finally {
            start.countDown()
            release.countDown()
            pool.shutdownNow()
            assertTrue(pool.awaitTermination(2, TimeUnit.SECONDS))
            dir.deleteRecursively()
        }
    }

    @Test fun failedThumbnailFallsBackToOriginalAndRetriesWithoutReextracting() {
        val dir = Files.createTempDirectory("dlna-thumb-failure").toFile()
        val original = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47)
        var extractions = 0
        var thumbnails = 0
        val provider = EngineMetadataProvider({ "{}" }, { _, out ->
            extractions++
            File(out).writeBytes(original)
        }, dir, thumbnail = { _, dst, _ ->
            thumbnails++
            dst.writeText("partial")
            false
        })
        try {
            repeat(2) {
                val cover = provider.readCover("/failed.flac")!!
                assertArrayEquals(original, cover.first)
                assertEquals("image/png", cover.second)
                assertEquals(listOf(cacheKey("/failed.flac") + ".img"), dir.list()!!.toList())
            }
            assertEquals(1, extractions)
            assertEquals(2, thumbnails)
        } finally { dir.deleteRecursively() }
    }

    @Test fun thrownOrEmptyThumbnailFallsBackWithoutPublishingPartialFile() {
        for (throws in listOf(true, false)) {
            val dir = Files.createTempDirectory("dlna-thumb-invalid").toFile()
            val original = "RIFF1234WEBP".toByteArray()
            val provider = EngineMetadataProvider({ "{}" }, { _, out -> File(out).writeBytes(original) },
                dir, thumbnail = { _, dst, _ ->
                    if (throws) {
                        dst.writeText("partial")
                        throw IllegalStateException("decode failure")
                    }
                    true
                })
            try {
                val cover = provider.readCover("/invalid.flac")!!
                assertArrayEquals(original, cover.first)
                assertEquals("image/webp", cover.second)
                assertEquals(listOf(cacheKey("/invalid.flac") + ".img"), dir.list()!!.toList())
            } finally { dir.deleteRecursively() }
        }
    }

    @Test fun successfulThumbnailDeletesOriginalAndMtimeChangeReextracts() {
        val dir = Files.createTempDirectory("dlna-thumb-mtime").toFile()
        val song = File(dir, "song.flac").apply { writeText("audio") }
        val art = File(dir, "art")
        var extractions = 0
        var thumbnails = 0
        val bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 7)
        val provider = EngineMetadataProvider({ "{}" }, { _, out ->
            extractions++
            File(out).writeText("original")
        }, art, thumbnail = { _, dst, _ ->
            thumbnails++
            assertNotEquals(cacheKey(song.path) + "-t600.jpg", dst.name)
            assertFalse(File(art, cacheKey(song.path) + "-t600.jpg").exists())
            dst.writeBytes(bytes)
            true
        })
        try {
            val firstKey = cacheKey(song.path)
            assertArrayEquals(bytes, provider.readCover(song.path)!!.first)
            assertFalse(File(art, firstKey + ".img").exists())
            assertArrayEquals(bytes, File(art, firstKey + "-t600.jpg").readBytes())
            // A fresh provider must reuse the persisted thumbnail without extracting.
            val fresh = EngineMetadataProvider({ "{}" }, { _, _ -> fail("disk cache extracted") }, art,
                thumbnail = { _, _, _ -> fail("disk cache thumbnailed"); false })
            assertArrayEquals(bytes, fresh.readCover(song.path)!!.first)
            assertTrue(song.setLastModified(song.lastModified() + 2000))
            assertArrayEquals(bytes, provider.readCover(song.path)!!.first)
            assertEquals("image/jpeg", provider.readCover(song.path)!!.second)
            assertEquals(2, extractions)
            assertEquals(2, thumbnails)
            assertFalse(File(art, cacheKey(song.path) + ".img").exists())
            assertTrue(File(art, cacheKey(song.path) + "-t600.jpg").length() > 0)
            assertFalse(art.list()!!.any { it.endsWith(".tmp") })
        } finally { dir.deleteRecursively() }
    }

    @Test fun missingCoverWithThumbnailIsCachedWithoutThumbnailing() {
        val dir = Files.createTempDirectory("dlna-thumb-missing").toFile()
        var calls = 0
        val provider = EngineMetadataProvider({ "{}" }, { _, _ -> calls++ }, dir,
            thumbnail = { _, _, _ -> fail("missing art thumbnailed"); false })
        try {
            assertNull(provider.readCover("/missing.flac"))
            assertNull(provider.readCover("/missing.flac"))
            assertEquals(1, calls)
        } finally { dir.deleteRecursively() }
    }

    private fun cacheKey(path: String): String =
        MessageDigest.getInstance("SHA-1").digest(path.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) } + "-${File(path).lastModified()}"
}
