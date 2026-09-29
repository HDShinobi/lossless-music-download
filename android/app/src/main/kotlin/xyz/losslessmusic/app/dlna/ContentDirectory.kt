package xyz.losslessmusic.app.dlna

import java.io.File
import java.io.StringReader
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.xml.sax.InputSource

internal class BrowseResult(val didl: String, val numberReturned: Int, val totalMatches: Int)
internal data class BrowseRequest(val objectId: String, val flag: String, val startingIndex: Int, val requestedCount: Int)

internal class ContentDirectory(
    private val rootDir: String, private val friendlyName: String,
    private val baseUrl: () -> String, private val meta: MetadataProvider?,
) {
    private val tags = TagCache()
    private val root = File(rootDir).toPath().toAbsolutePath().normalize()

    private val nameOrder = Comparator<File> { a, b ->
        val left = a.name.toByteArray(StandardCharsets.UTF_8)
        val right = b.name.toByteArray(StandardCharsets.UTF_8)
        var difference = 0
        for (i in 0 until minOf(left.size, right.size)) {
            difference = (left[i].toInt() and 0xff) - (right[i].toInt() and 0xff)
            if (difference != 0) break
        }
        if (difference != 0) difference else left.size - right.size
    }

    companion object {
        private val OBJECT_ID_PATTERN = Regex("[A-Za-z0-9_-]*")
        val AUDIO_MIME: Map<String, String> = mapOf(
            ".flac" to "audio/flac", ".m4a" to "audio/mp4", ".mp3" to "audio/mpeg",
            ".alac" to "audio/mp4", ".opus" to "audio/ogg", ".ogg" to "audio/ogg",
            ".wav" to "audio/wav", ".aiff" to "audio/aiff", ".aif" to "audio/aiff",
        )

        fun mimeForExt(ext: String): String = AUDIO_MIME[ext.lowercase(Locale.ROOT)] ?: "application/octet-stream"

        fun encodeObjectId(relPath: String): String =
            Base64.getUrlEncoder().withoutPadding().encodeToString(relPath.toByteArray(StandardCharsets.UTF_8))

        fun decodeObjectId(id: String): String {
            require(OBJECT_ID_PATTERN.matches(id)) { "invalid object ID" }
            return try {
                String(Base64.getUrlDecoder().decode(id), StandardCharsets.UTF_8)
            } catch (e: IllegalArgumentException) {
                throw IllegalArgumentException("invalid object ID", e)
            }
        }

        fun parseBrowse(soapBody: String): Pair<String, String> =
            parseBrowse(soapBody, DocumentBuilderFactory.newInstance())

        internal fun parseBrowse(soapBody: String, factory: DocumentBuilderFactory): Pair<String, String> {
            val request = parseBrowseRequest(soapBody, factory)
            return request.objectId to request.flag
        }

        fun parseBrowseRequest(soapBody: String): BrowseRequest =
            parseBrowseRequest(soapBody, DocumentBuilderFactory.newInstance())

        internal fun parseBrowseRequest(soapBody: String, factory: DocumentBuilderFactory): BrowseRequest {
            require(!soapBody.contains("<!DOCTYPE", ignoreCase = true) &&
                !soapBody.contains("<!ENTITY", ignoreCase = true)) { "DTD declarations are forbidden" }
            factory.isNamespaceAware = true
            try { factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) } catch (_: Exception) { }
            try { factory.setFeature("http://xml.org/sax/features/external-general-entities", false) } catch (_: Exception) { }
            try { factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false) } catch (_: Exception) { }
            try { factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalDTD", "") } catch (_: Exception) { }
            try { factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalSchema", "") } catch (_: Exception) { }
            try { factory.isExpandEntityReferences = false } catch (_: Exception) { }
            val doc = factory.newDocumentBuilder().parse(InputSource(StringReader(soapBody)))
            val id = doc.getElementsByTagNameNS("*", "ObjectID")
            val flag = doc.getElementsByTagNameNS("*", "BrowseFlag")
            require(id.length > 0 && flag.length > 0) { "missing Browse fields" }
            fun number(field: String): Int {
                val nodes = doc.getElementsByTagNameNS("*", field)
                if (nodes.length == 0) return 0
                val value = nodes.item(0).textContent.trim().toIntOrNull()
                require(value != null && value >= 0) { "invalid $field" }
                return value
            }
            return BrowseRequest(id.item(0).textContent, flag.item(0).textContent,
                number("StartingIndex"), number("RequestedCount"))
        }

        fun validateRelPath(relPath: String) {
            if (File(relPath).isAbsolute || relPath.split(File.separatorChar).any { it == ".." }) {
                throw SecurityException("path escapes root: $relPath")
            }
        }
    }

    private fun resolve(encodedId: String): File {
        val rel = decodeObjectId(encodedId)
        validateRelPath(rel)
        val path = root.resolve(rel).normalize()
        if (!path.startsWith(root)) throw SecurityException("path escapes root")
        return path.toFile()
    }

    fun resolveFile(encodedId: String): File? = resolve(encodedId).takeIf { it.isFile }

    fun browse(objectId: String, startingIndex: Int = 0, requestedCount: Int = 0): BrowseResult {
        require(startingIndex >= 0 && requestedCount >= 0) { "invalid pagination" }
        val rel = if (objectId == "0") "" else decodeObjectId(objectId)
        val target = if (objectId == "0") root.toFile() else resolve(objectId)
        if (!target.isDirectory) throw IllegalArgumentException("directory not found: $objectId")
        val entries = (target.listFiles() ?: emptyArray()).asSequence()
            .filter { !it.name.startsWith('.') && (it.isDirectory ||
                (it.isFile && AUDIO_MIME.containsKey(".${it.name.substringAfterLast('.', "").lowercase(Locale.ROOT)}"))) }
            .sortedWith(nameOrder).toList()
        val ordered = entries.filter { it.isDirectory } + entries.filter { it.isFile }
        val total = ordered.size
        val selected = if (startingIndex >= total) emptyList() else ordered.drop(startingIndex)
            .let { if (requestedCount == 0) it else it.take(requestedCount) }
        val containers = mutableListOf<CdObject>()
        val items = mutableListOf<CdItem>()
        for (entry in selected) {
            val childRel = if (rel.isEmpty()) entry.name else "$rel/${entry.name}"
            val id = encodeObjectId(childRel)
            if (entry.isDirectory) {
                containers += CdObject(id, objectId, entry.name, countChildren(entry))
            } else if (entry.isFile) {
                val ext = entry.name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
                val mime = AUDIO_MIME[ext.lowercase(Locale.ROOT)] ?: continue
                val t = meta?.let { tags.get(entry.absolutePath, it) }
                val title = t?.title?.takeIf { it.isNotEmpty() } ?: entry.name.removeSuffix(ext)
                items += CdItem(id, objectId, title,
                    artist = t?.artist?.takeIf { it.isNotEmpty() } ?: t?.albumArtist.orEmpty(),
                    album = t?.album.orEmpty(), genre = t?.genre.orEmpty(), trackNumber = t?.trackNumber ?: 0,
                    albumArtUri = if (meta != null) "${baseUrl()}/art/$id" else "",
                    durationSec = t?.durationSec ?: 0, sampleRate = t?.sampleRate ?: 0,
                    bitDepth = t?.bitDepth ?: 0, bitrateKbps = t?.bitrateKbps ?: 0,
                    size = entry.length(), mime = mime, url = "${baseUrl()}/media/$id")
            }
        }
        return BrowseResult(Didl.lite(containers, items), selected.size, total)
    }

    fun browseMetadata(objectId: String): BrowseResult {
        require(objectId == "0") { "unsupported object ID: $objectId" }
        return BrowseResult(Didl.lite(listOf(CdObject("0", "-1", friendlyName, countChildren(root.toFile()))), emptyList()), 1, 1)
    }

    private fun countChildren(dir: File): Int = (dir.listFiles() ?: emptyArray()).count { entry ->
        !entry.name.startsWith('.') && (entry.isDirectory || (entry.isFile &&
            AUDIO_MIME.containsKey(".${entry.name.substringAfterLast('.', "").lowercase(Locale.ROOT)}")))
    }
}
