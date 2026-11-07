package xyz.losslessmusic.app

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class NativeQueuePolicyTest {
    @Test fun providerDefaultAllowsThreeConcurrentItems() = runBlocking {
        val entered = AtomicInteger()
        val release = CompletableDeferred<Unit>()
        val job = launch(Dispatchers.Default) {
            NativeQueueGate(3).runAll(listOf(1, 2, 3)) {
                entered.incrementAndGet()
                release.await()
            }
        }
        try {
            withTimeout(2000) { while (entered.get() < 3) delay(5) }
            release.complete(Unit)
            withTimeout(2000) { job.join() }
        } finally { job.cancelAndJoin() }
    }

    @Test fun stoppingRequeuesOnlyInFlightStates() {
        for (status in listOf("downloading", "finalizing")) {
            val item = NativeWorkerItemState("item", status = status, progress = 0.5,
                bytesReceived = 50, bytesTotal = 100)
            item.requeueOnStop()
            assertEquals("queued", item.status)
            assertEquals(0.0, item.progress, 0.0)
            assertEquals(0L, item.bytesReceived)
            assertEquals(0L, item.bytesTotal)
        }
        for (status in listOf("queued", "done", "failed")) {
            val item = NativeWorkerItemState("item", status = status, error = "kept")
            item.requeueOnStop()
            assertEquals(status, item.status)
            assertEquals("kept", item.error)
        }
    }

    @Test fun networkRequiresInternetAndAcceptsUnmeteredEthernet() {
        val gate = NativeQueueGate(1)
        gate.setNetwork(true, wifi = true, unmetered = true, internet = false)
        assertTrue(gate.isPaused)
        gate.setNetwork(true, wifi = false, unmetered = true, ethernet = true)
        assertFalse(gate.isPaused)
        gate.setNetwork(true, wifi = false, unmetered = false, ethernet = true)
        assertTrue(gate.isPaused)
    }

    @Test fun providerLimitSerializesSameProviderButAllowsOtherProviders() = runBlocking {
        val gate = NativeQueueGate(3)
        val entered = java.util.Collections.synchronizedList(mutableListOf<String>())
        val release = CompletableDeferred<Unit>()
        val job = launch(Dispatchers.Default) {
            gate.runAll(listOf("a", "a", "b"), providerKey = { it }, providerLimit = { 1 }) {
                entered.add(it)
                release.await()
            }
        }
        try {
            withTimeout(2000) { while (entered.size < 2) delay(5) }
            delay(100)
            assertEquals(1, entered.count { it == "a" })
            assertEquals(1, entered.count { it == "b" })
            release.complete(Unit)
            withTimeout(2000) { job.join() }
            assertEquals(2, entered.count { it == "a" })
        } finally { job.cancelAndJoin() }
    }

    @Test fun networkPolicyAndManualPauseAreIndependent() {
        val gate = NativeQueueGate(1)
        assertFalse(gate.isPaused)
        gate.setNetwork(true, wifi = false, unmetered = true)
        assertEquals("waiting_wifi", gate.pauseReason)
        gate.setPaused(true)
        gate.setNetwork(true, wifi = true, unmetered = true)
        assertEquals("paused", gate.pauseReason)
        gate.setPaused(false)
        assertFalse(gate.isPaused)
        gate.setNetwork(true, wifi = true, unmetered = false)
        assertTrue(gate.isPaused)
        gate.setNetwork(false, wifi = false, unmetered = false)
        assertFalse(gate.isPaused)
    }

    @Test fun limitsConcurrencyAndDrainsAdmittedItemsOnPause() = runBlocking {
        val gate = NativeQueueGate(2)
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val release = CompletableDeferred<Unit>()
        val jobs = List(5) { launch(Dispatchers.Default) {
            gate.withSlot {
                val n = active.incrementAndGet()
                peak.updateAndGet { maxOf(it, n) }
                release.await()
                active.decrementAndGet()
            }
        } }
        withTimeout(2000) { while (active.get() != 2) delay(5) }
        gate.setPaused(true)
        release.complete(Unit)
        withTimeout(2000) { while (active.get() != 0) delay(5) }
        delay(100)
        assertEquals(2, jobs.count { it.isCompleted })
        assertEquals(2, peak.get())
        gate.setPaused(false)
        withTimeout(2000) { jobs.joinAll() }
    }

    @Test fun concurrencyIsClamped() {
        assertEquals(1, NativeQueueGate(0).concurrency)
        assertEquals(3, NativeQueueGate(10).concurrency)
    }
    @Test fun defaultConcurrencyPreservesQueueOrder() = runBlocking {
        val gate = NativeQueueGate(1)
        val completed = mutableListOf<Int>()
        gate.runAll((1..20).toList()) { completed.add(it) }
        assertEquals((1..20).toList(), completed)
    }
}
