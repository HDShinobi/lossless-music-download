package xyz.losslessmusic.app.engine

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RustProbeStartGateTest {
    @Test fun startsOnlyAfterLoadWithAllInputsAndOnlyOnce() {
        val gate = RustProbeStartGate()
        val starts = mutableListOf<Triple<String, String, String>>()
        val start: (String, String, String) -> Unit = { ext, data, key ->
            starts.add(Triple(ext, data, key))
        }

        gate.afterLoad(debug = true, start)
        gate.captureKey("key")
        gate.afterLoad(debug = true, start)
        gate.captureDirs("extensions", "data")
        gate.afterLoad(debug = false, start)
        assertEquals(emptyList<Triple<String, String, String>>(), starts)

        gate.afterLoad(debug = true, start)
        gate.afterLoad(debug = true, start)
        assertEquals(listOf(Triple("extensions", "data", "key")), starts)
    }

    @Test fun concurrentLoadsLaunchOnlyOnce() {
        val gate = RustProbeStartGate()
        gate.captureKey("key")
        gate.captureDirs("extensions", "data")
        val pool = Executors.newFixedThreadPool(4)
        val ready = CountDownLatch(4)
        val go = CountDownLatch(1)
        val starts = java.util.concurrent.atomic.AtomicInteger()
        try {
            val jobs = (1..4).map {
                pool.submit {
                    ready.countDown()
                    go.await()
                    gate.afterLoad(debug = true) { _, _, _ -> starts.incrementAndGet() }
                }
            }
            org.junit.Assert.assertTrue(ready.await(5, TimeUnit.SECONDS))
            go.countDown()
            jobs.forEach { it.get(5, TimeUnit.SECONDS) }
            assertEquals(1, starts.get())
        } finally {
            pool.shutdownNow()
        }
    }
}
