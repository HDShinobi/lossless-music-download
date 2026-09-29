package xyz.losslessmusic.app.dlna

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.Random
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class SsdpTest {
    private val udn = "uuid:12345678-1234-5050-8080-123456789abc"
    private val location = "http://192.168.1.100:8200/description.xml"
    private val mediaServer = "urn:schemas-upnp-org:device:MediaServer:1"
    private val contentDirectory = "urn:schemas-upnp-org:service:ContentDirectory:1"
    private val responders = mutableListOf<SsdpResponder>()

    @After fun tearDown() { responders.forEach { it.stop() } }

    @Test fun aliveRootDeviceMatchesGoBytes() {
        assertEquals(
            "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\n" +
                "LOCATION: $location\r\nNT: upnp:rootdevice\r\nNTS: ssdp:alive\r\n" +
                "SERVER: Linux/5.0 UPnP/1.0 LosslessMusic/1.0\r\nUSN: $udn::upnp:rootdevice\r\n" +
                "BOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 1\r\n\r\n",
            SsdpMessages.alive(location, udn, "upnp:rootdevice", 42),
        )
    }

    @Test fun aliveDeviceUdnUsesBareUsn() {
        assertEquals(
            "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\n" +
                "LOCATION: $location\r\nNT: $udn\r\nNTS: ssdp:alive\r\n" +
                "SERVER: Linux/5.0 UPnP/1.0 LosslessMusic/1.0\r\nUSN: $udn\r\n" +
                "BOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 1\r\n\r\n",
            SsdpMessages.alive(location, udn, udn, 42),
        )
    }

    @Test fun aliveServiceUsesQualifiedUsn() {
        assertTrue(SsdpMessages.alive(location, udn, contentDirectory, 42)
            .contains("USN: $udn::$contentDirectory\r\n"))
    }

    @Test fun searchResponseMatchesGoBytes() {
        assertEquals(
            "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\n" +
                "DATE: Mon, 02 Jan 2006 15:04:05 GMT\r\nEXT:\r\nLOCATION: $location\r\n" +
                "SERVER: Linux/5.0 UPnP/1.0 LosslessMusic/1.0\r\nST: $mediaServer\r\n" +
                "USN: $udn::$mediaServer\r\nBOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 1\r\n\r\n",
            SsdpMessages.searchResponse(location, udn, mediaServer, 42, "Mon, 02 Jan 2006 15:04:05 GMT"),
        )
    }

    @Test fun byebyeMatchesGoBytes() {
        assertEquals(
            "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: upnp:rootdevice\r\n" +
                "NTS: ssdp:byebye\r\nUSN: $udn::upnp:rootdevice\r\n" +
                "BOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 1\r\n\r\n",
            SsdpMessages.byebye(udn, "upnp:rootdevice", 42),
        )
    }

    @Test fun upnp11HeadersAndDate() {
        assertTrue(SsdpMessages.alive(location, udn, udn, 7, 3).endsWith("BOOTID.UPNP.ORG: 7\r\nCONFIGID.UPNP.ORG: 3\r\n\r\n"))
        assertTrue(SsdpMessages.byebye(udn, udn, 7, 3).endsWith("BOOTID.UPNP.ORG: 7\r\nCONFIGID.UPNP.ORG: 3\r\n\r\n"))
        assertTrue(SsdpMessages.searchResponse(location, udn, udn, 7, "Tue, 05 Aug 2026 01:02:03 GMT", 3)
            .contains("DATE: Tue, 05 Aug 2026 01:02:03 GMT\r\n"))
        assertEquals("Thu, 01 Jan 1970 00:00:00 GMT", SsdpMessages.httpDate(0))
    }

    @Test fun searchResponseDelayIsBounded() {
        val random = Random(42)
        assertEquals(0L, SsdpMessages.searchResponseDelayMillis(0, random))
        assertEquals(0L, SsdpMessages.searchResponseDelayMillis(-5, random))
        repeat(200) {
            assertTrue(SsdpMessages.searchResponseDelayMillis(1, random) in 0L..1000L)
            assertTrue(SsdpMessages.searchResponseDelayMillis(30, random) in 0L..2000L)
        }
    }

    @Test fun parsesMSearchAndMatches() {
        val dg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nmx: 3\r\nst: ssdp:all\r\n\r\n"
        assertEquals("ssdp:all" to 3, SsdpMessages.parseMSearch(dg))
        assertEquals(listOf("upnp:rootdevice", udn, mediaServer, contentDirectory), SsdpMessages.matchingNts("ssdp:all", udn))
        assertEquals(listOf(udn), SsdpMessages.matchingNts(udn, udn))
        assertTrue(SsdpMessages.matchingNts("urn:schemas-upnp-org:device:MediaRenderer:1", udn).isEmpty())
        assertNull(SsdpMessages.parseMSearch("NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\n\r\n"))
        assertEquals("upnp:rootdevice" to 1, SsdpMessages.parseMSearch("M-SEARCH * HTTP/1.1\r\nST: upnp:rootdevice\r\nMX: -2\r\n\r\n"))
        assertNull(SsdpMessages.parseMSearch("M-SEARCH * HTTP/1.1\r\nMX: 1\r\n\r\n"))
    }

    @Test fun responderAnswersUnicastMSearchOnLoopback() {
        val loopback = "127.0.0.1"
        val localLocation = "http://127.0.0.1:8200/description.xml"
        val responder = SsdpResponder(loopback, localLocation, udn, listenPort = 0, joinMulticast = false)
        responders += responder
        responder.start()
        DatagramSocket(0, InetAddress.getByName(loopback)).use { client ->
            client.soTimeout = 3000
            val request = "M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\nMX: 0\r\n\r\n".toByteArray(StandardCharsets.UTF_8)
            client.send(DatagramPacket(request, request.size, InetAddress.getByName(loopback), responder.boundPort))
            val received = mutableSetOf<String>()
            repeat(4) {
                val packet = DatagramPacket(ByteArray(2048), 2048)
                client.receive(packet)
                assertEquals(InetAddress.getByName(loopback), packet.address)
                val response = String(packet.data, packet.offset, packet.length, StandardCharsets.UTF_8)
                assertTrue(response.startsWith("HTTP/1.1 200 OK\r\n"))
                assertTrue(response.contains("LOCATION: $localLocation\r\n"))
                received += response.lineSequence().first { it.startsWith("ST: ") }.trimEnd('\r').removePrefix("ST: ")
            }
            assertEquals(setOf("upnp:rootdevice", udn, mediaServer, contentDirectory), received)
        }
        responder.stop()
        responder.stop()
    }

    @Test fun nonLocalLanAddressFailsStartAndLeavesResponderStopped() {
        val responder = SsdpResponder("203.0.113.1", location, udn, listenPort = 0, joinMulticast = false)
        responders += responder
        try {
            responder.start()
            fail("Expected an IOException for a non-local bind address")
        } catch (_: IOException) {
            assertEquals(0, responder.boundPort)
        }
        responder.stop()
    }

    @Test fun receiveSocketFailureReportsCauseButNormalStopDoesNot() {
        val responder = SsdpResponder("127.0.0.1", location, udn, listenPort = 0, joinMulticast = false)
        responders += responder
        val failure = CountDownLatch(1)
        val calls = AtomicInteger()
        var message: String? = null
        responder.onFailure = {
            message = it
            calls.incrementAndGet()
            failure.countDown()
        }
        responder.start()
        responder.closeInboundForTest()
        assertTrue("Receive failure callback timed out", failure.await(3, TimeUnit.SECONDS))
        assertEquals("ssdp_failed: Socket closed", message)
        responder.stop()
        assertEquals(1, calls.get())

        val normallyStopped = SsdpResponder("127.0.0.1", location, udn, listenPort = 0, joinMulticast = false)
        responders += normallyStopped
        val normalCalls = AtomicInteger()
        normallyStopped.onFailure = { normalCalls.incrementAndGet() }
        normallyStopped.start()
        normallyStopped.stop()
        assertEquals(0, normalCalls.get())
    }
}
