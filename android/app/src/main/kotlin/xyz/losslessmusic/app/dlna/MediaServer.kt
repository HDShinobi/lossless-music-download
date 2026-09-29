package xyz.losslessmusic.app.dlna

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationStopped
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.cio.CIO
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.engine.embeddedServer
import io.ktor.server.http.content.LocalFileContent
import io.ktor.server.plugins.autohead.AutoHeadResponse
import io.ktor.server.plugins.partialcontent.PartialContent
import io.ktor.server.request.receiveText
import io.ktor.server.response.respond
import io.ktor.server.response.respondBytes
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import java.io.File
import java.net.BindException
import kotlinx.coroutines.runBlocking

/** HTTP portion of one DLNA MediaServer. The controller owns SSDP. */
class MediaServer(
    private val rootDir: String, val friendlyName: String, private val lanIp: String,
    private val meta: MetadataProvider?, private val preferredPort: Int = 8200,
) {
    val udn: String = DeviceDescription.stableUdn(friendlyName, rootDir)
    @Volatile var baseUrl: String = ""
        private set
    @Volatile var onUnexpectedStop: ((String) -> Unit)? = null
    @Volatile private var stopping = false
    private var engine: EmbeddedServer<*, *>? = null
    private val directory = ContentDirectory(rootDir, friendlyName, { baseUrl }, meta)

    @Synchronized fun start(): String {
        if (engine != null) return baseUrl
        stopping = false
        val started = try {
            startEngine(preferredPort)
        } catch (error: Exception) {
            if (preferredPort == 0 || !isBindFailure(error)) throw error
            startEngine(0)
        }
        try {
            val port = runBlocking { started.engine.resolvedConnectors().first().port }
            baseUrl = "http://$lanIp:$port"
            engine = started
            return baseUrl
        } catch (error: Exception) {
            stopping = true
            started.stop(500, 2000)
            throw error
        }
    }

    @Synchronized fun stop() {
        stopping = true
        val active = engine ?: return
        engine = null
        baseUrl = ""
        active.stop(gracePeriodMillis = 500, timeoutMillis = 2000)
    }

    private fun isBindFailure(error: Throwable): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is BindException) return true
            cause = cause.cause
        }
        return false
    }

    private fun startEngine(port: Int): EmbeddedServer<*, *> {
        val candidate = createEngine(port)
        try {
            candidate.start(wait = false)
        } catch (error: Exception) {
            stopping = true
            try {
                candidate.stop(gracePeriodMillis = 0, timeoutMillis = 0)
            } catch (cleanupError: Exception) {
                error.addSuppressed(cleanupError)
            } finally {
                stopping = false
            }
            throw error
        }
        return candidate
    }

    private fun createEngine(port: Int) = embeddedServer(CIO, host = lanIp, port = port) {
        install(PartialContent)
        install(AutoHeadResponse)
        monitor.subscribe(ApplicationStopped) {
            if (!stopping) onUnexpectedStop?.invoke("http_stopped")
        }
        routing {
            get("/description.xml") {
                call.respondText(DeviceDescription.xml(friendlyName, udn, baseUrl), ContentType.parse("text/xml; charset=utf-8"))
            }
            get("/cd/scpd") {
                call.respondText(DeviceDescription.contentDirectoryScpd(), ContentType.parse("text/xml; charset=utf-8"))
            }
            route("/cd/control") {
                post {
                    val body = try { call.receiveText() } catch (error: Exception) {
                        call.respondText("Bad Request", status = HttpStatusCode.BadRequest)
                        return@post
                    }
                    val (id, flag) = try { ContentDirectory.parseBrowse(body) } catch (error: Exception) {
                        call.respondText("Bad Request: ${error.message}", status = HttpStatusCode.BadRequest)
                        return@post
                    }
                    val result = try {
                        if (flag == "BrowseMetadata") directory.browseMetadata(id) else directory.browse(id)
                    } catch (error: Exception) {
                        call.respondText("Internal Server Error: ${error.message}", status = HttpStatusCode.InternalServerError)
                        return@post
                    }
                    call.respondText(buildBrowseResponse(result.didl, result.numberReturned, result.totalMatches),
                        ContentType.parse("text/xml; charset=utf-8"))
                }
                get { call.respondText("Method Not Allowed", status = HttpStatusCode.MethodNotAllowed) }
            }
            get("/media/{id}") {
                val file = resolve(call.parameters["id"]) ?: return@get
                val mime = ContentDirectory.mimeForExt(file.extension.let { ".$it" })
                if (call.request.headers["getcontentFeatures.dlna.org"] == "1")
                    call.response.headers.append("contentFeatures.dlna.org", Didl.contentFeatures(mime))
                call.response.headers.append("transferMode.dlna.org",
                    call.request.headers["transferMode.dlna.org"]?.takeIf { it.isNotEmpty() } ?: "Streaming")
                call.respond(LocalFileContent(file, ContentType.parse(mime)))
            }
            get("/art/{id}") {
                if (meta == null) {
                    call.respond(HttpStatusCode.NotFound)
                    return@get
                }
                val file = resolve(call.parameters["id"]) ?: return@get
                val cover = meta.readCover(file.absolutePath)
                if (cover == null || cover.first.isEmpty()) {
                    call.respond(HttpStatusCode.NotFound)
                    return@get
                }
                call.respondBytes(cover.first, ContentType.parse(cover.second.ifEmpty { "image/jpeg" }))
            }
        }
    }

    private suspend fun io.ktor.server.routing.RoutingContext.resolve(id: String?): File? {
        if (id.isNullOrEmpty()) {
            call.respond(HttpStatusCode.NotFound)
            return null
        }
        return try {
            directory.resolveFile(id) ?: run { call.respond(HttpStatusCode.NotFound); null }
        } catch (_: SecurityException) {
            call.respond(HttpStatusCode.Forbidden)
            null
        } catch (_: IllegalArgumentException) {
            call.respond(HttpStatusCode.BadRequest)
            null
        }
    }
}

internal fun buildBrowseResponse(didl: String, numberReturned: Int, totalMatches: Int): String =
    """<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <Result>${Xml.escape(didl)}</Result>
      <NumberReturned>$numberReturned</NumberReturned>
      <TotalMatches>$totalMatches</TotalMatches>
      <UpdateID>1</UpdateID>
    </u:BrowseResponse>
  </s:Body>
</s:Envelope>"""
