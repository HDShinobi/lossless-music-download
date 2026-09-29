package xyz.losslessmusic.app.dlna

import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.xml.parsers.DocumentBuilder
import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.parsers.ParserConfigurationException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ContentDirectoryTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun directory(root: File, meta: MetadataProvider? = null) =
        ContentDirectory(root.path, "My Music Server", { "http://127.0.0.1:8200" }, meta)

    @Test fun parseBrowse() {
        val body = """<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>"""
        assertEquals("0" to "BrowseDirectChildren", ContentDirectory.parseBrowse(body))
        assertEquals(ContentDirectory.encodeObjectId("Artist/Album") to "BrowseDirectChildren",
            ContentDirectory.parseBrowse(body.replace("<ObjectID>0</ObjectID>", "<ObjectID>QXJ0aXN0L0FsYnVt</ObjectID>")))
    }

    @Test fun parseBrowseRejectsDoctype() {
        val evil = """<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>&e;</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>"""
        assertThrows(Exception::class.java) { ContentDirectory.parseBrowse(evil) }
        assertThrows(Exception::class.java) { ContentDirectory.parseBrowse("<broken") }
    }

    @Test fun parseBrowseRejectsDeclarationsWhenFactoryHasNoHardeningFeatures() {
        val normal = """<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>"""
        val factory = NoHardeningFactory()
        assertEquals("0" to "BrowseDirectChildren", ContentDirectory.parseBrowse(normal, factory))
        for (declaration in listOf("<!DOCTYPE x>", "<!doctype x>", "<!ENTITY x 'value'>", "<!entity x 'value'>")) {
            assertThrows(IllegalArgumentException::class.java) {
                ContentDirectory.parseBrowse(declaration + normal, NoHardeningFactory())
            }
        }
    }

    private class NoHardeningFactory : DocumentBuilderFactory() {
        private val delegate = DocumentBuilderFactory.newInstance()
        override fun newDocumentBuilder(): DocumentBuilder {
            delegate.isNamespaceAware = isNamespaceAware
            return delegate.newDocumentBuilder()
        }
        override fun setAttribute(name: String, value: Any) { throw IllegalArgumentException(name) }
        override fun getAttribute(name: String): Any { throw IllegalArgumentException(name) }
        override fun setFeature(name: String, value: Boolean) { throw ParserConfigurationException(name) }
        override fun getFeature(name: String): Boolean { throw ParserConfigurationException(name) }
    }

    @Test fun browseRoot() {
        val root = tmp.newFolder("lib")
        File(root, "Artist/Album").mkdirs()
        File(root, "Artist/Album/01 Song.flac").writeText("FAKEFLAC")
        val result = directory(root).browse("0")
        assertEquals(1, result.numberReturned)
        assertEquals(1, result.totalMatches)
        assertTrue(result.didl.contains("Artist"))
        assertTrue(result.didl.contains("storageFolder"))
        assertTrue(result.didl.contains("childCount=\"1\""))
    }

    @Test fun browseSubDir() {
        val root = tmp.newFolder("lib")
        val album = File(root, "Artist/Album").apply { mkdirs() }
        File(album, "01 Song.flac").writeText("FAKEFLAC")
        File(album, "02 Track.mp3").writeText("FAKEMP3")
        val id = ContentDirectory.encodeObjectId("Artist/Album")
        val result = directory(root).browse(id)
        assertEquals(2, result.numberReturned)
        assertTrue(result.didl.contains("01 Song"))
        assertTrue(result.didl.contains("audio/flac"))
        assertTrue(result.didl.contains("/media/"))
        assertTrue(result.didl.contains("parentID=\"$id\""))
    }

    @Test fun browseTraversalRejected() {
        val cd = directory(tmp.newFolder("lib"))
        for (rel in listOf("../secret", "a/../secret", "/outside")) {
            assertThrows(SecurityException::class.java) { cd.browse(ContentDirectory.encodeObjectId(rel)) }
            assertThrows(SecurityException::class.java) { cd.resolveFile(ContentDirectory.encodeObjectId(rel)) }
        }
        assertThrows(IllegalArgumentException::class.java) { cd.browse("%bad") }
    }

    @Test fun encodeDecodeObjectId() {
        for (path in listOf("Artist/Album", "Artist/Album/01 Song.flac", "simple")) {
            assertEquals(path, ContentDirectory.decodeObjectId(ContentDirectory.encodeObjectId(path)))
        }
        assertThrows(IllegalArgumentException::class.java) { ContentDirectory.decodeObjectId("a") }
    }

    @Test fun objectIdRoundTripsUnicodeNames() {
        val rel = "Sơn Tùng M-TP/Chúng Ta Của Hiện Tại & <Live> 🎵.flac"
        assertEquals(rel, ContentDirectory.decodeObjectId(ContentDirectory.encodeObjectId(rel)))
        assertFalse(ContentDirectory.encodeObjectId(rel).contains("="))
    }

    @Test fun browseMetadataRoot() {
        val root = tmp.newFolder("lib")
        File(root, "Artist").mkdir()
        val result = directory(root).browseMetadata("0")
        assertEquals(1, result.numberReturned)
        assertEquals(1, result.totalMatches)
        assertTrue(result.didl.contains("<container id=\"0\""))
        assertTrue(result.didl.contains("My Music Server"))
        assertTrue(result.didl.contains("object.container.storageFolder"))
        assertTrue(result.didl.contains("childCount=\"1\""))
        assertThrows(IllegalArgumentException::class.java) { directory(root).browseMetadata("other") }
    }

    @Test fun mimeForExt() {
        val cases = mapOf(".flac" to "audio/flac", ".FLAC" to "audio/flac", ".mp3" to "audio/mpeg",
            ".m4a" to "audio/mp4", ".alac" to "audio/mp4", ".wav" to "audio/wav",
            ".ogg" to "audio/ogg", ".opus" to "audio/ogg", ".aiff" to "audio/aiff",
            ".aif" to "audio/aiff", ".txt" to "application/octet-stream")
        for ((ext, mime) in cases) assertEquals(mime, ContentDirectory.mimeForExt(ext))
    }

    @Test fun browseWithMetadataProvider() {
        val root = tmp.newFolder("lib")
        File(root, "song.flac").writeText("x")
        val meta = object : MetadataProvider {
            override fun readTags(absPath: String) = TrackTags("Hello", "Adele", "25", genre = "Pop",
                trackNumber = 2, durationSec = 295, sampleRate = 44100, bitDepth = 16, bitrateKbps = 900)
            override fun readCover(absPath: String): Pair<ByteArray, String>? = byteArrayOf(1) to "image/jpeg"
        }
        val xml = directory(root, meta).browse("0").didl
        for (value in listOf("Hello", "Adele", "<upnp:album>25</upnp:album>", "Pop",
            "originalTrackNumber", "/art/", "0:04:55", "bitrate=\"112500\"")) {
            assertTrue("missing $value", xml.contains(value))
        }
    }

    @Test fun browseListsEntriesSortedByName() {
        val root = tmp.newFolder("lib")
        File(root, "b.flac").writeText("x")
        File(root, "A.flac").writeText("x")
        File(root, "c").mkdir()
        val xml = directory(root).browse("0").didl
        val order = Regex("<dc:title>([^<]*)</dc:title>").findAll(xml).map { it.groupValues[1] }.toList()
        assertEquals(listOf("c", "A", "b"), order)
    }

    @Test fun browseSortsUnicodeNamesByUtf8Bytes() {
        val root = tmp.newFolder("lib")
        File(root, "🎵.flac").writeText("x")
        File(root, "\uE000.flac").writeText("x")
        val xml = directory(root).browse("0").didl
        val order = Regex("<dc:title>([^<]*)</dc:title>").findAll(xml).map { it.groupValues[1] }.toList()
        assertEquals(listOf("\uE000", "🎵"), order)
    }

    @Test fun metadataFallsBackToFilenameAndAlbumArtist() {
        val root = tmp.newFolder("lib")
        File(root, "song.flac").writeText("x")
        val meta = object : MetadataProvider {
            override fun readTags(absPath: String) = TrackTags(albumArtist = "Band")
            override fun readCover(absPath: String): Pair<ByteArray, String>? = null
        }
        val xml = directory(root, meta).browse("0").didl
        assertTrue(xml.contains("<dc:title>song</dc:title>"))
        assertTrue(xml.contains("<dc:creator>Band</dc:creator>"))
        assertTrue(xml.contains("<upnp:albumArtURI"))
    }

    @Test fun tagCacheRefreshesOnModifiedFileAndCachesNull() {
        val file = tmp.newFile("song.flac")
        var reads = 0
        val meta = object : MetadataProvider {
            override fun readTags(absPath: String): TrackTags? { reads++; return if (reads == 1) null else TrackTags(title = "Updated") }
            override fun readCover(absPath: String): Pair<ByteArray, String>? = null
        }
        val cache = TagCache()
        assertNull(cache.get(file.absolutePath, meta))
        assertNull(cache.get(file.absolutePath, meta))
        assertEquals(1, reads)
        file.setLastModified(file.lastModified() + 5000)
        assertEquals("Updated", cache.get(file.absolutePath, meta)?.title)
        assertEquals(2, reads)
    }

    @Test fun tagCacheDoesNotHoldLockDuringProviderRead() {
        val first = tmp.newFile("first.flac")
        val second = tmp.newFile("second.flac")
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val provider = object : MetadataProvider {
            override fun readTags(absPath: String): TrackTags? {
                if (absPath == first.absolutePath) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                }
                return TrackTags(title = File(absPath).name)
            }
            override fun readCover(absPath: String): Pair<ByteArray, String>? = null
        }
        val cache = TagCache()
        val pool = Executors.newFixedThreadPool(2)
        try {
            val blocked = pool.submit<TrackTags?> { cache.get(first.absolutePath, provider) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val concurrent = pool.submit<TrackTags?> { cache.get(second.absolutePath, provider) }
            assertEquals("second.flac", concurrent.get(2, TimeUnit.SECONDS)?.title)
            release.countDown()
            assertEquals("first.flac", blocked.get(2, TimeUnit.SECONDS)?.title)
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }

    @Test fun resolveFileOnlyReturnsRegularFiles() {
        val root = tmp.newFolder("lib")
        File(root, "song.flac").writeText("x")
        val cd = directory(root)
        assertEquals(File(root, "song.flac"), cd.resolveFile(ContentDirectory.encodeObjectId("song.flac")))
        assertNull(cd.resolveFile(ContentDirectory.encodeObjectId("missing.flac")))
        assertNull(cd.resolveFile(ContentDirectory.encodeObjectId(".")))
    }
}
