package xyz.losslessmusic.app.dlna

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FinalFixTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun failureCallbackDuringConcurrentStopDoesNotWaitForStopping() {
        val stopEntered = CountDownLatch(1)
        val callbackEntered = CountDownLatch(1)
        val callbackFinished = CountDownLatch(1)
        val releaseStop = CountDownLatch(1)
        lateinit var runtime: DlnaRuntime
        val controller = MediaServerController({ _, _, _ -> object : DlnaRuntime {
            override var onFailure: ((String) -> Unit)? = null
            override fun start() = "http://192.168.1.2:8200"
            override fun stop() {
                stopEntered.countDown()
                check(callbackEntered.await(2, TimeUnit.SECONDS))
                check(callbackFinished.await(2, TimeUnit.SECONDS))
                check(releaseStop.await(2, TimeUnit.SECONDS))
            }
        }.also { runtime = it } }, {}, {})
        controller.start("/music", "N", "192.168.1.2")
        controller.beforeFailureShutdownForTest = {
            callbackEntered.countDown()
            check(stopEntered.await(2, TimeUnit.SECONDS))
        }
        val callback = runtime.onFailure!!
        val failing = thread {
            callback("ssdp_failed")
            callbackFinished.countDown()
        }
        try {
            assertTrue(callbackEntered.await(2, TimeUnit.SECONDS))
            val stopping = thread { controller.stop() }
            assertTrue(stopEntered.await(2, TimeUnit.SECONDS))
            assertTrue("failure callback blocked in STOPPING", callbackFinished.await(1, TimeUnit.SECONDS))
            failing.join(2000)
            releaseStop.countDown()
            stopping.join(2000)
            assertFalse(stopping.isAlive)
        } finally {
            releaseStop.countDown()
        }
        assertEquals("STOPPED", controller.state.name)
    }

    @Test fun browsePagesBeforeReadingTags() {
        val root = tmp.newFolder("library")
        File(root, "folder").mkdir()
        for (name in listOf("a.flac", "b.flac", "c.flac", "d.flac")) File(root, name).writeText("x")
        val reads = mutableListOf<String>()
        val meta = object : MetadataProvider {
            override fun readTags(absPath: String): TrackTags? {
                reads += File(absPath).name
                return null
            }
            override fun readCover(absPath: String): Pair<ByteArray, String>? = null
        }
        val cd = ContentDirectory(root.path, "N", { "http://127.0.0.1:8200" }, meta)
        fun titles(result: BrowseResult) = Regex("<dc:title>([^<]*)</dc:title>")
            .findAll(result.didl).map { it.groupValues[1] }.toList()
        assertEquals(listOf("folder", "a"), titles(cd.browse("0", 0, 2)))
        assertEquals(listOf("b", "c"), titles(cd.browse("0", 2, 2)))
        assertEquals(0, cd.browse("0", 10, 2).numberReturned)
        assertEquals(5, cd.browse("0", 0, 0).numberReturned)
        assertEquals(5, cd.browse("0", 2, 2).totalMatches)
        assertEquals(listOf("a.flac", "b.flac", "c.flac", "d.flac"), reads)
    }

    @Test fun parseBrowsePaginationDefaultsAndValues() {
        val body = "<Browse><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></Browse>"
        assertEquals(0, ContentDirectory.parseBrowseRequest(body).startingIndex)
        assertEquals(0, ContentDirectory.parseBrowseRequest(body).requestedCount)
        val page = body.replace("</Browse>", "<StartingIndex>2</StartingIndex><RequestedCount>3</RequestedCount></Browse>")
        assertEquals(2, ContentDirectory.parseBrowseRequest(page).startingIndex)
        assertEquals(3, ContentDirectory.parseBrowseRequest(page).requestedCount)
    }

    @Test fun ssdpStartFailureStopsHttpAndRethrows() {
        val events = mutableListOf<String>()
        val failure = IllegalStateException("ssdp bind failed")
        val runtime = RealDlnaRuntime(fakeHttp(events), { _, _ -> fakeSsdp(events, failure) })
        assertSame(failure, assertThrows(IllegalStateException::class.java) { runtime.start() })
        assertEquals(listOf("http.start", "ssdp.start", "ssdp.stop", "http.stop"), events)
    }

    @Test fun runtimeStopsSsdpBeforeHttp() {
        val events = mutableListOf<String>()
        val runtime = RealDlnaRuntime(fakeHttp(events), { _, _ -> fakeSsdp(events) })
        runtime.start()
        runtime.stop()
        assertEquals(listOf("http.start", "ssdp.start", "ssdp.stop", "http.stop"), events)
    }

    private fun fakeHttp(events: MutableList<String>) = object : DlnaHttpTransport {
        override val udn = "uuid:test"
        override var onUnexpectedStop: ((String) -> Unit)? = null
        override fun start(): String { events += "http.start"; return "http://127.0.0.1:8200" }
        override fun stop() { events += "http.stop" }
    }

    private fun fakeSsdp(events: MutableList<String>, failure: Throwable? = null) = object : DlnaSsdpTransport {
        override var onFailure: ((String) -> Unit)? = null
        override fun start() { events += "ssdp.start"; failure?.let { throw it } }
        override fun stop() { events += "ssdp.stop" }
    }

    @Test fun controlPaginatesAndRejectsOversizedBody() {
        val root = tmp.newFolder("http-library")
        for (name in listOf("a.flac", "b.flac", "c.flac")) File(root, name).writeText("x")
        val server = MediaServer(root.path, "N", "127.0.0.1", null, preferredPort = 0)
        server.start()
        try {
            fun post(body: String): HttpURLConnection =
                (URL(server.baseUrl + "/cd/control").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "text/xml")
                    outputStream.use { it.write(body.toByteArray()) }
                }
            val body = "<Browse><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag>" +
                "<StartingIndex>1</StartingIndex><RequestedCount>1</RequestedCount></Browse>"
            val page = post(body)
            assertEquals(200, page.responseCode)
            val response = page.inputStream.bufferedReader().readText()
            assertTrue(response.contains("<NumberReturned>1</NumberReturned>"))
            assertTrue(response.contains("<TotalMatches>3</TotalMatches>"))
            assertTrue(response.contains("b"))
            assertEquals(413, post("x".repeat(65537)).responseCode)
        } finally {
            server.stop()
        }
    }
}
