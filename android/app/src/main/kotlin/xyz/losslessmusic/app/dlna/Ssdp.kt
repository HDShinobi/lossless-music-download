package xyz.losslessmusic.app.dlna

import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.net.SocketException
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Random
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

internal object SsdpMessages {
    const val MULTICAST_HOST = "239.255.255.250:1900"
    const val SERVER_BANNER = "Linux/5.0 UPnP/1.0 LosslessMusic/1.0"
    const val CONFIG_ID = 1
    private const val ROOT = "upnp:rootdevice"
    private const val MEDIA_SERVER = "urn:schemas-upnp-org:device:MediaServer:1"
    private const val CONTENT_DIRECTORY = "urn:schemas-upnp-org:service:ContentDirectory:1"

    fun nts(udn: String): List<String> = listOf(ROOT, udn, MEDIA_SERVER, CONTENT_DIRECTORY)

    private fun usn(udn: String, nt: String): String = if (nt == udn) udn else "$udn::$nt"

    fun alive(location: String, udn: String, nt: String, bootId: Int, configId: Int = CONFIG_ID): String =
        "NOTIFY * HTTP/1.1\r\n" +
            "HOST: $MULTICAST_HOST\r\n" +
            "CACHE-CONTROL: max-age=1800\r\n" +
            "LOCATION: $location\r\n" +
            "NT: $nt\r\n" +
            "NTS: ssdp:alive\r\n" +
            "SERVER: $SERVER_BANNER\r\n" +
            "USN: ${usn(udn, nt)}\r\n" +
            "BOOTID.UPNP.ORG: $bootId\r\n" +
            "CONFIGID.UPNP.ORG: $configId\r\n\r\n"

    fun byebye(udn: String, nt: String, bootId: Int, configId: Int = CONFIG_ID): String =
        "NOTIFY * HTTP/1.1\r\n" +
            "HOST: $MULTICAST_HOST\r\n" +
            "NT: $nt\r\n" +
            "NTS: ssdp:byebye\r\n" +
            "USN: ${usn(udn, nt)}\r\n" +
            "BOOTID.UPNP.ORG: $bootId\r\n" +
            "CONFIGID.UPNP.ORG: $configId\r\n\r\n"

    fun searchResponse(location: String, udn: String, st: String, bootId: Int, date: String, configId: Int = CONFIG_ID): String =
        "HTTP/1.1 200 OK\r\n" +
            "CACHE-CONTROL: max-age=1800\r\n" +
            "DATE: $date\r\n" +
            "EXT:\r\n" +
            "LOCATION: $location\r\n" +
            "SERVER: $SERVER_BANNER\r\n" +
            "ST: $st\r\n" +
            "USN: ${usn(udn, st)}\r\n" +
            "BOOTID.UPNP.ORG: $bootId\r\n" +
            "CONFIGID.UPNP.ORG: $configId\r\n\r\n"

    fun httpDate(epochMillis: Long): String = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("GMT")
    }.format(Date(epochMillis))

    fun parseMSearch(datagram: String): Pair<String, Int>? {
        val lines = datagram.split("\r\n")
        if (!lines[0].startsWith("M-SEARCH")) return null
        var st = ""
        var mx = 1
        for (line in lines.drop(1)) {
            when {
                line.startsWith("ST:", ignoreCase = true) -> st = line.substring(3).trim()
                line.startsWith("MX:", ignoreCase = true) -> {
                    val value = line.substring(3).trim().toIntOrNull()
                    if (value != null && value >= 0) mx = value
                }
            }
        }
        return if (st.isEmpty()) null else st to mx
    }

    fun matchingNts(st: String, udn: String): List<String> = when (st) {
        "ssdp:all" -> nts(udn)
        ROOT, MEDIA_SERVER, CONTENT_DIRECTORY -> listOf(st)
        udn -> listOf(udn)
        else -> emptyList()
    }

    fun searchResponseDelayMillis(mx: Int, random: Random): Long =
        if (mx <= 0) 0 else random.nextInt((minOf(mx.toLong() * 1000, 2000L) + 1).toInt()).toLong()
}

/** SSDP receiver and advertiser bound to the supplied LAN address. */
class SsdpResponder internal constructor(
    private val lanIp: String,
    private val location: String,
    private val udn: String,
    private val listenPort: Int,
    private val joinMulticast: Boolean,
) {
    constructor(lanIp: String, location: String, udn: String) : this(lanIp, location, udn, 1900, true)

    @Volatile var onFailure: ((String) -> Unit)? = null
    @Volatile internal var boundPort: Int = 0
        private set
    @Volatile private var running = false
    @Volatile private var generation = 0L
    private var inbound: MulticastSocket? = null
    private var outbound: MulticastSocket? = null
    private var scheduler: ScheduledExecutorService? = null
    private var receiver: Thread? = null
    private var bootId = 0
    private val random = Random()
    private val group = InetAddress.getByName("239.255.255.250")

    @Synchronized @Throws(IOException::class)
    fun start() {
        if (running) return
        val lanAddr = InetAddress.getByName(lanIp)
        val nif = NetworkInterface.getByInetAddress(lanAddr)
        var input: MulticastSocket? = null
        var output: MulticastSocket? = null
        try {
            input = MulticastSocket(null).apply {
                reuseAddress = true
                bind(InetSocketAddress(listenPort))
                if (nif != null) {
                    networkInterface = nif
                    // Android's single-argument join ignores setInterface (ifindex 0).
                    if (joinMulticast) joinGroup(InetSocketAddress(group, 0), nif)
                } else {
                    // No interface resolved: retain the default-route membership fallback.
                    @Suppress("DEPRECATION")
                    fun joinDefault() {
                        setInterface(lanAddr)
                        if (joinMulticast) joinGroup(group)
                    }
                    joinDefault()
                }
                // Test-only loopback mode keeps the socket unjoined.
                timeToLive = 4
                soTimeout = 1000
            }
            output = MulticastSocket(InetSocketAddress(lanAddr, 0)).apply {
                if (nif != null) networkInterface = nif else {
                    @Suppress("DEPRECATION")
                    fun selectDefault() { setInterface(lanAddr) }
                    selectDefault()
                }
                timeToLive = 4
            }
            bootId = (System.currentTimeMillis() / 1000).toInt()
            boundPort = input.localPort
            inbound = input
            outbound = output
            val runGeneration = ++generation
            running = true
            scheduler = Executors.newSingleThreadScheduledExecutor { task ->
                Thread(task, "ssdp-scheduled").apply { isDaemon = true }
            }
            sendAlive()
            scheduler!!.scheduleAtFixedRate({ if (isCurrent(runGeneration)) sendAlive() }, 30, 30, TimeUnit.SECONDS)
            receiver = Thread({ receiveLoop(input, runGeneration) }, "ssdp-receiver").apply { isDaemon = true; start() }
        } catch (error: Exception) {
            running = false
            generation++
            scheduler?.shutdownNow()
            scheduler = null
            input?.close()
            output?.close()
            inbound = null
            outbound = null
            boundPort = 0
            if (error is IOException) throw error
            throw IOException("SSDP start failed", error)
        }
    }

    fun stop() {
        val thread: Thread?
        synchronized(this) {
            if (!running) return
            running = false
            generation++
            scheduler?.shutdownNow()
            scheduler = null
            sendByebye()
            inbound?.close()
            outbound?.close()
            inbound = null
            outbound = null
            boundPort = 0
            thread = receiver
            receiver = null
        }
        if (thread !== Thread.currentThread()) {
            try { thread?.join(2000) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        }
    }

    @Synchronized internal fun closeInboundForTest() { inbound?.close() }

    private fun isCurrent(runGeneration: Long): Boolean = running && generation == runGeneration

    private fun receiveLoop(socket: MulticastSocket, runGeneration: Long) {
        val buffer = ByteArray(2048)
        while (isCurrent(runGeneration)) {
            val packet = DatagramPacket(buffer, buffer.size)
            try {
                socket.receive(packet)
                val request = SsdpMessages.parseMSearch(String(packet.data, packet.offset, packet.length, StandardCharsets.UTF_8)) ?: continue
                val matches = SsdpMessages.matchingNts(request.first, udn)
                if (matches.isEmpty()) continue
                val destination = InetSocketAddress(packet.address, packet.port)
                val delay = SsdpMessages.searchResponseDelayMillis(request.second, random)
                scheduler?.schedule({ if (isCurrent(runGeneration)) sendSearchResponses(destination, matches, runGeneration) }, delay, TimeUnit.MILLISECONDS)
            } catch (_: SocketTimeoutException) {
                // Wake periodically to observe stop().
            } catch (error: SocketException) {
                fail(error, runGeneration)
                return
            } catch (error: Exception) {
                fail(error, runGeneration)
                return
            }
        }
    }

    private fun fail(error: Exception, runGeneration: Long) {
        val callback = synchronized(this) { if (isCurrent(runGeneration)) onFailure else null }
        callback?.invoke("ssdp_failed: ${error.message ?: error.javaClass.simpleName}")
    }

    private fun sendSearchResponses(destination: InetSocketAddress, matches: List<String>, runGeneration: Long) {
        try {
            DatagramSocket(null).use { socket ->
                socket.bind(InetSocketAddress(InetAddress.getByName(lanIp), 0))
                val date = SsdpMessages.httpDate(System.currentTimeMillis())
                for (st in matches) {
                    if (!isCurrent(runGeneration)) break
                    send(socket, SsdpMessages.searchResponse(location, udn, st, bootId, date), destination)
                }
            }
        } catch (_: IOException) {
            // UDP response failure is transient; the receive loop remains available.
        }
    }

    private fun sendAlive() {
        val socket = outbound ?: return
        val destination = InetSocketAddress(group, 1900)
        try {
            repeat(2) { for (nt in SsdpMessages.nts(udn)) send(socket, SsdpMessages.alive(location, udn, nt, bootId), destination) }
        } catch (_: IOException) {
            // UDP advertisement failure does not invalidate an opened listener.
        }
    }

    private fun sendByebye() {
        val socket = outbound ?: return
        val destination = InetSocketAddress(group, 1900)
        try {
            for (nt in SsdpMessages.nts(udn)) send(socket, SsdpMessages.byebye(udn, nt, bootId), destination)
        } catch (_: IOException) {
            // Stop still closes all resources.
        }
    }

    private fun send(socket: DatagramSocket, message: String, destination: InetSocketAddress) {
        val bytes = message.toByteArray(StandardCharsets.UTF_8)
        socket.send(DatagramPacket(bytes, bytes.size, destination))
    }
}
