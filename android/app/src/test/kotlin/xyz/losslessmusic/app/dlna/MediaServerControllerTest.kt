package xyz.losslessmusic.app.dlna

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MediaServerControllerTest {
    private class FakeRuntime(private val events: MutableList<String>) : DlnaRuntime {
        override var onFailure: ((String) -> Unit)? = null
        var startError: Throwable? = null
        var stopError: Throwable? = null
        var startEntered: CountDownLatch? = null
        var finishStart: CountDownLatch? = null
        var stopEntered: CountDownLatch? = null
        var finishStop: CountDownLatch? = null
        override fun start(): String {
            events += "runtime.start"
            startEntered?.countDown()
            finishStart?.await(3, TimeUnit.SECONDS)
            startError?.let { throw it }
            return "http://192.168.1.2:8200"
        }
        override fun stop() {
            events += "runtime.stop"
            stopError?.let { throw it }
            stopEntered?.countDown()
            finishStop?.await(3, TimeUnit.SECONDS)
        }
    }

    @Test fun startIsOrderedAndIdempotent() {
        val events = mutableListOf<String>()
        var factoryCalls = 0
        val controller = MediaServerController({ _, _, _ -> factoryCalls++; FakeRuntime(events) },
            { events += "lock.acquire" }, { events += "lock.release" })
        val first = controller.start("/music", "MyServer", "192.168.1.2")
        assertEquals("RUNNING", JSONObject(first).getString("state"))
        assertEquals(first, controller.start("/music", "Other", "192.168.1.2"))
        assertEquals(1, factoryCalls)
        assertEquals(listOf("lock.acquire", "runtime.start"), events)
    }

    @Test fun differentIpRestartsRunningServer() {
        val events = mutableListOf<String>()
        val ips = mutableListOf<String>()
        val controller = MediaServerController({ _, _, ip -> ips += ip; FakeRuntime(events) },
            { events += "acquire" }, { events += "release" })
        controller.start("/m", "N", "192.168.1.2")
        assertEquals("RUNNING", JSONObject(controller.start("/m", "N", "192.168.1.3")).getString("state"))
        assertEquals(listOf("192.168.1.2", "192.168.1.3"), ips)
        assertEquals(listOf("acquire", "runtime.start", "runtime.stop", "release", "acquire", "runtime.start"), events)
    }

    @Test fun errorDuringStartReleasesLockAndAllowsStopAndRetry() {
        val events = mutableListOf<String>()
        var calls = 0
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).apply {
            if (++calls == 1) startError = NoClassDefFoundError("ktor_missing")
        } }, { events += "acquire" }, { events += "release" })
        assertEquals("FAILED", JSONObject(controller.start("/m", "N", "192.168.1.2")).getString("state"))
        assertEquals("ktor_missing", (controller.state as ServerState.Failed).reason)
        assertEquals(1, events.count { it == "release" })
        val stopped = thread { controller.stop() }
        stopped.join(2000)
        assertFalse(stopped.isAlive)
        assertEquals("STOPPED", controller.state.name)
        assertEquals("RUNNING", JSONObject(controller.start("/m", "N", "192.168.1.2")).getString("state"))
        assertEquals(2, calls)
    }

    @Test fun errorDuringShutdownReleasesLockAndSignalsWaiters() {
        val events = mutableListOf<String>()
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).apply { stopError = LinkageError("stop_broken") } },
            { events += "acquire" }, { events += "release" })
        controller.start("/m", "N", "192.168.1.2")
        controller.stop()
        assertTrue(controller.state.name == "STOPPED" || controller.state.name == "FAILED")
        assertEquals(1, events.count { it == "release" })
        val stopped = thread { controller.stop() }
        stopped.join(2000)
        assertFalse(stopped.isAlive)
    }

    @Test fun startingCanBeCancelledOrFailedWithoutLeakingLock() {
        for (mode in listOf("stop", "network", "failure")) {
            val events = mutableListOf<String>()
            val entered = CountDownLatch(1)
            val finish = CountDownLatch(1)
            lateinit var candidate: FakeRuntime
            val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).also {
                candidate = it; it.startEntered = entered; it.finishStart = finish
            } }, { events += "acquire" }, { events += "release" })
            val starting = thread { controller.start("/m", "N", "192.168.1.2") }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            val stopping = when (mode) {
                "stop" -> thread { controller.stop() }
                "network" -> thread { controller.onNetworkChanged("192.168.1.3") }
                else -> thread { candidate.onFailure?.invoke("ssdp_failed") }
            }
            if (mode != "failure") {
                Thread.sleep(50)
                assertEquals("STARTING", controller.state.name)
            }
            finish.countDown()
            starting.join(2000); stopping.join(2000)
            assertFalse(starting.isAlive); assertFalse(stopping.isAlive)
            assertEquals(if (mode == "stop") "STOPPED" else "FAILED", controller.state.name)
            assertEquals(1, events.count { it == "release" })
        }
    }

    @Test fun lateFailureFromPreviousRuntimeDoesNotFailStartingCandidate() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        var calls = 0
        lateinit var old: FakeRuntime
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(mutableListOf()).also {
            if (++calls == 1) old = it else { it.startEntered = entered; it.finishStart = finish }
        } }, {}, {})
        controller.start("/m", "N", "192.168.1.2")
        val lateCallback = old.onFailure!!
        controller.stop()
        val starting = thread { controller.start("/m", "N", "192.168.1.2") }
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        lateCallback("old_runtime_failed")
        finish.countDown()
        starting.join(2000)
        assertFalse(starting.isAlive)
        assertEquals("RUNNING", controller.state.name)
    }

    @Test fun cleanupErrorAfterFailedStartStillReleasesLock() {
        val events = mutableListOf<String>()
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).apply {
            startError = NoClassDefFoundError("missing")
            stopError = LinkageError("cleanup_broken")
        } }, { events += "acquire" }, { events += "release" })
        assertEquals("FAILED", JSONObject(controller.start("/m", "N", "192.168.1.2")).getString("state"))
        assertEquals(1, events.count { it == "release" })
        controller.stop()
        assertEquals("STOPPED", controller.state.name)
    }

    @Test fun failureReleasesLockAndLaterStartRetries() {
        val events = mutableListOf<String>()
        var count = 0
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).apply {
            if (++count == 1) startError = IllegalStateException("bind_failed")
        } }, { events += "lock.acquire" }, { events += "lock.release" })
        assertEquals("bind_failed", JSONObject(controller.start("/m", "N", "192.168.1.2")).getString("error"))
        assertEquals("FAILED", controller.state.name)
        assertEquals("RUNNING", JSONObject(controller.start("/m", "N", "192.168.1.2")).getString("state"))
        assertEquals(2, count)
        assertEquals(listOf("lock.acquire", "runtime.start", "runtime.stop", "lock.release", "lock.acquire", "runtime.start"), events)
    }

    @Test fun stopIsIdempotentAndClearsFailure() {
        val events = mutableListOf<String>()
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events) }, { events += "acquire" }, { events += "release" })
        controller.start("/m", "N", "192.168.1.2")
        controller.stop(); controller.stop()
        assertEquals("STOPPED", controller.state.name)
        assertEquals(listOf("acquire", "runtime.start", "runtime.stop", "release"), events)
        controller.start("/m", "N", "")
        assertEquals("FAILED", controller.state.name)
        controller.stop()
        assertEquals("STOPPED", controller.state.name)
        assertEquals(1, events.count { it == "runtime.stop" })
    }

    @Test fun runtimeAndNetworkFailuresCleanUp() {
        val events = mutableListOf<String>()
        lateinit var runtime: FakeRuntime
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).also { runtime = it } },
            { events += "acquire" }, { events += "release" })
        controller.start("/m", "N", "192.168.1.2")
        controller.onNetworkChanged("192.168.1.2")
        assertEquals("RUNNING", controller.state.name)
        runtime.onFailure?.invoke("ssdp_failed: x")
        assertEquals(ServerState.Failed("ssdp_failed: x"), controller.state)
        assertEquals(listOf("acquire", "runtime.start", "runtime.stop", "release"), events)
        controller.start("/m", "N", "192.168.1.2")
        controller.onNetworkChanged(null)
        assertEquals(ServerState.Failed("network_changed"), controller.state)
        controller.start("/m", "N", "192.168.1.2")
        controller.onNetworkChanged("192.168.1.3")
        assertEquals(ServerState.Failed("network_changed"), controller.state)
    }

    @Test fun emptyIpDoesNotCreateRuntimeAndStatusHasExactKeys() {
        var called = false
        val controller = MediaServerController({ _, _, _ -> called = true; FakeRuntime(mutableListOf()) }, {}, {})
        val json = JSONObject(controller.start("/m", "N", ""))
        assertFalse(called)
        assertEquals(setOf("running", "url", "name", "state", "error"), json.keys().asSequence().toSet())
        assertFalse(json.getBoolean("running"))
        assertEquals("", json.getString("url"))
        assertEquals("N", json.getString("name"))
        assertEquals("FAILED", json.getString("state"))
        assertEquals("no_lan_ip", json.getString("error"))
    }

    @Test fun startWaitsForSlowStop() {
        val events = mutableListOf<String>()
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        var count = 0
        val controller = MediaServerController({ _, _, _ -> FakeRuntime(events).apply {
            if (++count == 1) { stopEntered = entered; finishStop = finish }
        } }, {}, {})
        controller.start("/m", "N", "192.168.1.2")
        val stopping = thread { controller.stop() }
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        val starting = thread { controller.start("/m", "N", "192.168.1.2") }
        Thread.sleep(100)
        assertEquals(1, count)
        finish.countDown()
        stopping.join(2000); starting.join(2000)
        assertEquals(2, count)
        assertEquals("RUNNING", controller.state.name)
    }
}
