package xyz.losslessmusic.app.dlna

import java.io.StringReader
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.xml.sax.InputSource

class DeviceDescriptionTest {
    private fun parse(xml: String) = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(InputSource(StringReader(xml)))

    @Test fun deviceDescriptionXml() {
        val xml = DeviceDescription.xml("My Music", "uuid:test-udn-1234", "http://192.168.1.10:8200")
        assertEquals("root", parse(xml).documentElement.tagName)
        for (value in listOf("urn:schemas-upnp-org:device:MediaServer:1",
            "urn:schemas-upnp-org:service:ContentDirectory:1", "My Music", "uuid:test-udn-1234", "/cd/control")) {
            assertTrue("missing $value", xml.contains(value))
        }
    }

    @Test fun contentDirectoryScpd() {
        val xml = DeviceDescription.contentDirectoryScpd()
        assertEquals("scpd", parse(xml).documentElement.tagName)
        assertTrue(xml.contains("Browse"))
        assertTrue(xml.contains("BrowseDirectChildren"))
    }

    @Test fun stableUdn() {
        val first = DeviceDescription.stableUdn("MyServer", "/music")
        assertEquals(first, DeviceDescription.stableUdn("MyServer", "/music"))
        assertTrue(first != DeviceDescription.stableUdn("OtherServer", "/music"))
        assertTrue(first.startsWith("uuid:"))
    }

    @Test fun stableUdnGoldens() {
        assertEquals("uuid:fc083821-6359-5af1-9a79-b927fcbff497", DeviceDescription.stableUdn("MyServer", "/music"))
        assertEquals("uuid:dab3fed1-0cb5-5f89-b2e6-88a82ae0213c", DeviceDescription.stableUdn("OtherServer", "/music"))
        assertEquals("uuid:c82df54b-1365-50d9-b953-335434373319", DeviceDescription.stableUdn("Lossless Music", "/storage/emulated/0/Music"))
    }
}
