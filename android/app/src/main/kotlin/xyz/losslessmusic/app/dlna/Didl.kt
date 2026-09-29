package xyz.losslessmusic.app.dlna

internal object Xml {
    /** Matches Go encoding/xml.EscapeText for the characters used by DIDL. */
    fun escape(s: String): String = buildString {
        for (char in s) append(when (char) {
            '&' -> "&amp;"
            '<' -> "&lt;"
            '>' -> "&gt;"
            '"' -> "&#34;"
            '\'' -> "&#39;"
            '\t' -> "&#x9;"
            '\n' -> "&#xA;"
            '\r' -> "&#xD;"
            else -> char.toString()
        })
    }

    fun attr(s: String): String = "\"${escape(s)}\""
}

internal data class CdObject(val id: String, val parentId: String, val title: String, val childCount: Int)

internal data class CdItem(
    val id: String, val parentId: String, val title: String,
    val artist: String = "", val album: String = "", val genre: String = "",
    val trackNumber: Int = 0, val albumArtUri: String = "",
    val durationSec: Int = 0, val sampleRate: Int = 0, val bitDepth: Int = 0, val bitrateKbps: Int = 0,
    val size: Long = 0, val mime: String, val url: String,
)

internal object Didl {
    private const val FLAGS = "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"

    fun formatDuration(sec: Int): String = if (sec <= 0) "" else
        "%d:%02d:%02d".format(java.util.Locale.ROOT, sec / 3600, (sec % 3600) / 60, sec % 60)

    fun protocolInfoFor(mime: String): String =
        "http-get:*:$mime:${contentFeatures(mime)}"

    fun contentFeatures(mime: String): String =
        if (mime == "audio/mpeg") "DLNA.ORG_PN=MP3;$FLAGS" else FLAGS

    fun bitrateBytesPerSec(kbps: Int): Int = if (kbps <= 0) 0 else kbps * 1000 / 8

    fun lite(containers: List<CdObject>, items: List<CdItem>): String = buildString {
        append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        append("<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"")
        append(" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"")
        append(" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"")
        append(" xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\">\n")

        for (container in containers) {
            append("  <container id=${Xml.attr(container.id)} parentID=${Xml.attr(container.parentId)} restricted=\"1\" childCount=\"${container.childCount}\">\n")
            append("    <dc:title>${Xml.escape(container.title)}</dc:title>\n")
            append("    <upnp:class>object.container.storageFolder</upnp:class>\n")
            append("  </container>\n")
        }

        for (item in items) {
            append("  <item id=${Xml.attr(item.id)} parentID=${Xml.attr(item.parentId)} restricted=\"1\">\n")
            element("dc:title", item.title)
            append("    <upnp:class>object.item.audioItem.musicTrack</upnp:class>\n")
            element("dc:creator", item.artist)
            element("upnp:artist", item.artist)
            element("upnp:album", item.album)
            element("upnp:genre", item.genre)
            if (item.trackNumber > 0) append("    <upnp:originalTrackNumber>${item.trackNumber}</upnp:originalTrackNumber>\n")
            if (item.albumArtUri.isNotEmpty()) {
                append("    <upnp:albumArtURI dlna:profileID=\"JPEG_TN\">${Xml.escape(item.albumArtUri)}</upnp:albumArtURI>\n")
            }
            append("    <res protocolInfo=${Xml.attr(protocolInfoFor(item.mime))}")
            if (item.size > 0) append(" size=\"${item.size}\"")
            val duration = formatDuration(item.durationSec)
            if (duration.isNotEmpty()) append(" duration=${Xml.attr(duration)}")
            val bitrate = bitrateBytesPerSec(item.bitrateKbps)
            if (bitrate > 0) append(" bitrate=\"$bitrate\"")
            if (item.sampleRate > 0) append(" sampleFrequency=\"${item.sampleRate}\"")
            if (item.bitDepth > 0) append(" bitsPerSample=\"${item.bitDepth}\"")
            append(">${Xml.escape(item.url)}</res>\n")
            append("  </item>\n")
        }
        append("</DIDL-Lite>")
    }

    private fun StringBuilder.element(tag: String, value: String) {
        if (value.isNotEmpty()) append("    <$tag>${Xml.escape(value)}</$tag>\n")
    }
}
