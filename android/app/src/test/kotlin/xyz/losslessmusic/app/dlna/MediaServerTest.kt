package xyz.losslessmusic.app.dlna

import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.nio.file.Files
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class MediaServerTest {
    private lateinit var root: File
    private val servers = mutableListOf<MediaServer>()
    private lateinit var server: MediaServer

    @Before fun setUp() {
        root = Files.createTempDirectory("dlna-http").toFile()
        File(root, "Artist/Album").mkdirs()
        File(root, "Artist/Album/01 Song.flac").writeText("FLACDATA")
        server = start()
    }

    @After fun tearDown() {
        servers.asReversed().forEach { it.stop() }
        root.deleteRecursively()
    }

    private fun start(name: String = "LosslessMusic Test", provider: MetadataProvider? = null): MediaServer =
        MediaServer(root.path, name, "127.0.0.1", provider, preferredPort = 0).also {
            servers += it
            it.start()
        }

    private fun get(path: String): HttpURLConnection =
        (URL(server.baseUrl + path).openConnection() as HttpURLConnection)

    private fun browse(id: String, flag: String = "BrowseDirectChildren"): HttpURLConnection {
        val body = """<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>$id</ObjectID><BrowseFlag>$flag</BrowseFlag></u:Browse></s:Body></s:Envelope>"""
        return get("/cd/control").apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "text/xml")
            outputStream.use { it.write(body.toByteArray()) }
        }
    }

    @Test fun serverDescriptionXML() {
        val c = get("/description.xml")
        assertEquals(200, c.responseCode)
        assertEquals("text/xml; charset=utf-8", c.contentType)
        val body = c.inputStream.bufferedReader().readText()
        assertTrue(body.contains("LosslessMusic Test"))
        assertTrue(body.contains("MediaServer:1"))
        assertTrue(body.contains("ContentDirectory:1"))
        DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(body.byteInputStream())
    }

    @Test fun serverBrowseRoot() {
        val c = browse("0")
        assertEquals(200, c.responseCode)
        val body = c.inputStream.bufferedReader().readText()
        assertTrue(body.contains("BrowseResponse"))
        assertTrue(body.contains("Artist"))
        assertTrue(body.contains("storageFolder"))
        assertTrue(body.contains("<NumberReturned>1</NumberReturned>"))
    }

    @Test fun serverBrowseAlbum() {
        val c = browse(ContentDirectory.encodeObjectId("Artist/Album"))
        assertEquals(200, c.responseCode)
        val body = c.inputStream.bufferedReader().readText()
        assertTrue(body.contains("01 Song"))
        assertTrue(body.contains("/media/"))
        assertTrue(body.contains("audioItem.musicTrack"))
    }

    @Test fun serverMediaFile() {
        val c = get("/media/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}")
        assertEquals(200, c.responseCode)
        assertEquals("FLACDATA", c.inputStream.bufferedReader().readText())
    }

    @Test fun serverMediaTraversalForbidden() {
        assertEquals(403, get("/media/${ContentDirectory.encodeObjectId("../secret")}").responseCode)
        assertEquals(400, get("/media/invalid!").responseCode)
        assertEquals(404, get("/media/${ContentDirectory.encodeObjectId("absent.flac")}").responseCode)
    }

    @Test fun serverStatus() {
        val notStarted = MediaServer(root.path, "Not started", "127.0.0.1", null, preferredPort = 0)
        assertEquals("", notStarted.baseUrl)
        assertEquals("LosslessMusic Test", server.friendlyName)
        assertEquals(DeviceDescription.stableUdn(server.friendlyName, root.path), server.udn)
        assertTrue(server.baseUrl.startsWith("http://127.0.0.1:"))
    }

    @Test fun serverStop() {
        val base = server.baseUrl
        server.stop()
        assertEquals("", server.baseUrl)
        assertThrows(java.net.ConnectException::class.java) {
            (URL("$base/description.xml").openConnection() as HttpURLConnection).responseCode
        }
    }

    @Test fun handlersViaRealServer() {
        assertEquals(200, get("/description.xml").responseCode)
        assertTrue(get("/cd/scpd").inputStream.bufferedReader().readText().contains("Browse"))
        assertEquals(200, browse("0").responseCode)
        assertEquals(200, get("/media/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}").responseCode)
    }

    @Test fun browseMetadataViaControl() {
        val c = browse("0", "BrowseMetadata")
        assertEquals(200, c.responseCode)
        val body = c.inputStream.bufferedReader().readText()
        assertTrue(body.contains("&lt;container id=&#34;0&#34;"))
        assertTrue(body.contains("<NumberReturned>1</NumberReturned>"))
        assertTrue(body.contains("<TotalMatches>1</TotalMatches>"))
    }

    @Test fun artWithoutProvider() {
        assertEquals(404, get("/art/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}").responseCode)
    }

    @Test fun artWithProvider() {
        val artServer = start(provider = object : MetadataProvider {
            override fun readTags(absPath: String): TrackTags? = null
            override fun readCover(absPath: String): Pair<ByteArray, String>? = byteArrayOf(1, 2, 3) to "image/png"
        })
        val c = URL("${artServer.baseUrl}/art/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}").openConnection() as HttpURLConnection
        assertEquals(200, c.responseCode)
        assertEquals("image/png", c.contentType)
        assertEquals("3", c.getHeaderField("Content-Length"))
        assertArrayEquals(byteArrayOf(1, 2, 3), c.inputStream.readBytes())
    }

    @Test fun artResponseHasOneContentLengthHeader() {
        val artServer = start(provider = object : MetadataProvider {
            override fun readTags(absPath: String): TrackTags? = null
            override fun readCover(absPath: String): Pair<ByteArray, String>? = byteArrayOf(1, 2, 3) to "image/png"
        })
        val port = URL(artServer.baseUrl).port
        Socket("127.0.0.1", port).use { socket ->
            socket.soTimeout = 5_000
            socket.getOutputStream().write(
                "GET /art/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".toByteArray()
            )
            val headers = socket.getInputStream().bufferedReader().use { reader ->
                generateSequence { reader.readLine()?.takeIf { it.isNotEmpty() } }.toList()
            }
            assertTrue(headers.first().contains("200"))
            assertEquals(1, headers.count { it.startsWith("Content-Length:", ignoreCase = true) })
        }
    }

    @Test fun rangeRequestsReturnPartialContent() {
        val data = ByteArray(10_000) { (it % 251).toByte() }
        File(root, "t.flac").writeBytes(data)
        val path = "/media/${ContentDirectory.encodeObjectId("t.flac")}"
        fun ranged(value: String) = get(path).apply { setRequestProperty("Range", value) }
        ranged("bytes=100-").let { assertEquals(206, it.responseCode); assertEquals("bytes 100-9999/10000", it.getHeaderField("Content-Range")); assertArrayEquals(data.copyOfRange(100, 10_000), it.inputStream.readBytes()) }
        ranged("bytes=-500").let { assertEquals(206, it.responseCode); assertEquals("bytes 9500-9999/10000", it.getHeaderField("Content-Range")); assertArrayEquals(data.copyOfRange(9500, 10_000), it.inputStream.readBytes()) }
        ranged("bytes=0-0").let { assertEquals(206, it.responseCode); assertEquals(1, it.inputStream.readBytes().size) }
        ranged("bytes=20000-").let { assertEquals(416, it.responseCode); assertEquals("bytes */10000", it.getHeaderField("Content-Range")) }
        get(path).let { assertEquals(200, it.responseCode); assertEquals("bytes", it.getHeaderField("Accept-Ranges")); assertEquals("audio/flac", it.contentType) }
    }

    @Test fun headReturnsHeadersOnly() {
        File(root, "t.flac").writeBytes(ByteArray(1234))
        val c = get("/media/${ContentDirectory.encodeObjectId("t.flac")}")
        c.requestMethod = "HEAD"
        assertEquals(200, c.responseCode)
        assertEquals("1234", c.getHeaderField("Content-Length"))
        assertEquals(0, c.inputStream.readBytes().size)
    }

    @Test fun dlnaHeadersOnMedia() {
        File(root, "t.flac").writeBytes(ByteArray(10))
        val c = get("/media/${ContentDirectory.encodeObjectId("t.flac")}")
        c.setRequestProperty("getcontentFeatures.dlna.org", "1")
        assertEquals(Didl.contentFeatures("audio/flac"), c.getHeaderField("contentFeatures.dlna.org"))
        assertEquals("Streaming", c.getHeaderField("transferMode.dlna.org"))
    }

    @Test fun contentFeaturesAbsentWhenNotRequested() {
        val c = get("/media/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}")
        assertEquals(200, c.responseCode)
        assertNull(c.getHeaderField("contentFeatures.dlna.org"))
    }

    @Test fun dlnaHeadersOnRangeResponse() {
        val c = get("/media/${ContentDirectory.encodeObjectId("Artist/Album/01 Song.flac")}")
        c.setRequestProperty("Range", "bytes=0-3")
        c.setRequestProperty("getcontentFeatures.dlna.org", "1")
        c.setRequestProperty("transferMode.dlna.org", "Interactive")
        assertEquals(206, c.responseCode)
        assertEquals("Interactive", c.getHeaderField("transferMode.dlna.org"))
        assertEquals(Didl.contentFeatures("audio/flac"), c.getHeaderField("contentFeatures.dlna.org"))
    }

    @Test fun fallsBackWhenPort8200Busy() {
        ServerSocket(0, 50, InetAddress.getByName("127.0.0.1")).use { busy ->
            val s = MediaServer(root.path, "Srv", "127.0.0.1", null, preferredPort = busy.localPort)
            servers += s
            val unexpectedStops = mutableListOf<String>()
            s.onUnexpectedStop = { unexpectedStops += it }
            assertFalse(s.start().endsWith(":${busy.localPort}"))
            assertTrue(unexpectedStops.isEmpty())
        }
    }

    @Test fun normalStopDoesNotInvokeUnexpectedStop() {
        val unexpectedStops = mutableListOf<String>()
        server.onUnexpectedStop = { unexpectedStops += it }
        server.stop()
        assertTrue(unexpectedStops.isEmpty())
    }

    @Test fun restartAfterStopRebinds() {
        server.stop()
        val base = server.start()
        assertEquals(200, (URL("$base/description.xml").openConnection() as HttpURLConnection).responseCode)
    }

    @Test fun stopWithOpenStreamReturnsPromptly() {
        File(root, "big.flac").writeBytes(ByteArray(20_000_000))
        val c = get("/media/${ContentDirectory.encodeObjectId("big.flac")}")
        c.inputStream.read(ByteArray(1024))
        val t0 = System.nanoTime()
        server.stop()
        assertTrue((System.nanoTime() - t0) / 1_000_000 < 5_000)
        c.disconnect()
    }

    @Test fun controlRejectsGet() {
        assertEquals(405, get("/cd/control").responseCode)
        assertEquals(405, get("/cd/control").apply { requestMethod = "PUT" }.responseCode)
    }

    @Test fun controlRejectsUnsafeXml() {
        val c = get("/cd/control").apply {
            requestMethod = "POST"
            doOutput = true
            outputStream.use { it.write("<!DOCTYPE x [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]><x>&secret;</x>".toByteArray()) }
        }
        assertEquals(400, c.responseCode)
    }
}
