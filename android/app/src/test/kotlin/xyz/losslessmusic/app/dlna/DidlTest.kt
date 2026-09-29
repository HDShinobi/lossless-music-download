package xyz.losslessmusic.app.dlna

import java.io.StringReader
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.xml.sax.InputSource

class DidlTest {
    private fun parse(xml: String) = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(InputSource(StringReader(xml)))

    @Test fun didlLite() {
        val xml = Didl.lite(
            listOf(CdObject("abc123", "0", "My Album", 3)),
            listOf(CdItem("def456", "abc123", "01 Song Title", artist = "The Artist", album = "My Album",
                size = 123456, mime = "audio/flac", url = "http://192.168.1.10:8200/media/def456")),
        )
        assertEquals("DIDL-Lite", parse(xml).documentElement.tagName)
        for (value in listOf("object.container.storageFolder", "object.item.audioItem.musicTrack",
            "My Album", "01 Song Title", "The Artist", "http-get:*:audio/flac:DLNA.ORG_OP=01",
            "http://192.168.1.10:8200/media/def456", "size=\"123456\"")) {
            assertTrue("missing $value", xml.contains(value))
        }
    }

    @Test fun didlLiteXmlEscaping() {
        val xml = Didl.lite(emptyList(), listOf(CdItem("x", "0", "Track with <special> & \"chars\"",
            size = 100, mime = "audio/mpeg", url = "http://host/media/x")))
        parse(xml)
        assertTrue(xml.contains("Track with &lt;special&gt; &amp; &#34;chars&#34;"))
    }

    @Test fun didlLiteEmpty() {
        val xml = Didl.lite(emptyList(), emptyList())
        assertEquals("DIDL-Lite", parse(xml).documentElement.tagName)
    }

    @Test fun formatDuration() {
        for ((sec, want) in mapOf(0 to "", -1 to "", 45 to "0:00:45", 225 to "0:03:45", 3661 to "1:01:01")) {
            assertEquals("seconds=$sec", want, Didl.formatDuration(sec))
        }
    }

    @Test fun bitrateBytesPerSec() {
        assertEquals(176375, Didl.bitrateBytesPerSec(1411))
        assertEquals(40000, Didl.bitrateBytesPerSec(320))
        assertEquals(0, Didl.bitrateBytesPerSec(0))
    }

    @Test fun protocolInfoFor() {
        assertTrue(Didl.protocolInfoFor("audio/mpeg").contains("DLNA.ORG_PN=MP3"))
        for (mime in listOf("audio/mpeg", "audio/flac", "audio/mp4")) {
            val info = Didl.protocolInfoFor(mime)
            assertTrue(info.startsWith("http-get:*:$mime:"))
            assertTrue(info.contains("DLNA.ORG_OP=01"))
            assertTrue(info.contains("DLNA.ORG_FLAGS="))
            assertEquals(info.substringAfterLast(':'), Didl.contentFeatures(mime))
        }
        assertFalse(Didl.protocolInfoFor("audio/flac").contains("DLNA.ORG_PN"))
    }

    @Test fun didlItemFullMetadata() {
        val xml = Didl.lite(emptyList(), listOf(CdItem("aWQ", "0", "Easy On Me", artist = "Adele",
            album = "30", genre = "Pop", trackNumber = 1,
            albumArtUri = "http://192.168.1.9:8200/art/aWQ", durationSec = 225,
            sampleRate = 44100, bitDepth = 16, bitrateKbps = 900, size = 1234,
            mime = "audio/flac", url = "http://192.168.1.9:8200/media/aWQ")))
        for (value in listOf("xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\"",
            "<dc:title>Easy On Me</dc:title>", "<dc:creator>Adele</dc:creator>",
            "<upnp:artist>Adele</upnp:artist>", "<upnp:album>30</upnp:album>",
            "<upnp:genre>Pop</upnp:genre>", "<upnp:originalTrackNumber>1</upnp:originalTrackNumber>",
            "<upnp:albumArtURI dlna:profileID=\"JPEG_TN\">http://192.168.1.9:8200/art/aWQ</upnp:albumArtURI>",
            "duration=\"0:03:45\"", "sampleFrequency=\"44100\"", "bitsPerSample=\"16\"",
            "bitrate=\"112500\"", "http-get:*:audio/flac:")) {
            assertTrue("missing $value", xml.contains(value))
        }
    }

    @Test fun didlItemOmitsUnknownFields() {
        val xml = Didl.lite(emptyList(), listOf(CdItem("x", "0", "track01", size = 10,
            mime = "audio/flac", url = "http://h/media/x")))
        for (value in listOf("<dc:creator>", "<upnp:artist>", "<upnp:album>", "<upnp:genre>",
            "<upnp:originalTrackNumber>", "<upnp:albumArtURI", "duration=", "bitrate=")) {
            assertFalse("unexpected $value", xml.contains(value))
        }
    }

    @Test fun didlEscapesLikeGo() {
        assertEquals("a&amp;b&lt;c&gt;d&#34;e&#39;f&#x9;g&#xA;h&#xD;i", Xml.escape("a&b<c>d\"e'f\tg\nh\ri"))
        val xml = Didl.lite(listOf(CdObject("aWQ", "0", "Sơn Tùng & \"Friends\" 🎵", 2)), emptyList())
        assertTrue(xml.contains("<dc:title>Sơn Tùng &amp; &#34;Friends&#34; 🎵</dc:title>"))
    }
}
