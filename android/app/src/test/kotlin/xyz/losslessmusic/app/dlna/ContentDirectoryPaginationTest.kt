package xyz.losslessmusic.app.dlna

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ContentDirectoryPaginationTest {
    private fun body(start: String, count: String) = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
            <ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag>
            <StartingIndex>$start</StartingIndex><RequestedCount>$count</RequestedCount>
          </u:Browse></s:Body>
        </s:Envelope>
    """.trimIndent()

    @Test fun blankPaginationDefaultsToZero() {
        val request = ContentDirectory.parseBrowseRequest(body("", "   "))
        assertEquals(0, request.startingIndex)
        assertEquals(0, request.requestedCount)
    }

    @Test fun ui4MaximumClampsToIntMaximum() {
        val request = ContentDirectory.parseBrowseRequest(body("4294967295", "4294967295"))
        assertEquals(Int.MAX_VALUE, request.startingIndex)
        assertEquals(Int.MAX_VALUE, request.requestedCount)
    }

    @Test fun nonNumericAndNegativePaginationIsRejected() {
        for (value in listOf("abc", "-1")) {
            assertThrows(IllegalArgumentException::class.java) {
                ContentDirectory.parseBrowseRequest(body(value, "0"))
            }
            assertThrows(IllegalArgumentException::class.java) {
                ContentDirectory.parseBrowseRequest(body("0", value))
            }
        }
    }
}
