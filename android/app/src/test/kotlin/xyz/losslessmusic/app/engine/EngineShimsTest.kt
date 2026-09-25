package xyz.losslessmusic.app.engine

import com.zarz.spotiflac.FFmpegRunner
import com.zarz.spotiflac.RunningFFmpeg
import com.zarz.spotiflac.runCancellable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class EngineShimsTest {
    private class FakeRun(
        private val finishAfterPolls: Int,
        private val success: Boolean,
        private val out: String,
    ) : RunningFFmpeg {
        val polls = AtomicInteger(0)
        val cancelled = AtomicBoolean(false)
        override fun isDone() = polls.incrementAndGet() > finishAfterPolls
        override fun succeeded() = success
        override fun output() = out
        override fun cancel() { cancelled.set(true) }
    }

    private fun runnerOf(run: FakeRun) = object : FFmpegRunner {
        var lastArgs: Array<String>? = null
        override fun start(arguments: Array<String>): RunningFFmpeg { lastArgs = arguments; return run }
    }

    @Test fun successReturnsTrueAndOutput() {
        val run = FakeRun(finishAfterPolls = 2, success = true, out = "ok-log")
        val result = runCancellable(runnerOf(run), arrayOf("-i", "a", "b"), { false }, pollMs = 1)
        assertEquals(true to "ok-log", result)
        assertFalse(run.cancelled.get())
    }

    @Test fun failureReturnsFalseWithFallbackMessage() {
        val run = FakeRun(finishAfterPolls = 0, success = false, out = "")
        val result = runCancellable(runnerOf(run), arrayOf("x"), { false }, pollMs = 1)
        assertEquals(false to "FFmpeg failed", result)
    }

    @Test fun cancelStopsSessionAndReportsCancelled() {
        val run = FakeRun(finishAfterPolls = Int.MAX_VALUE, success = true, out = "")
        var asked = 0
        val result = runCancellable(runnerOf(run), arrayOf("x"), { ++asked >= 3 }, pollMs = 1)
        assertEquals(false to "cancelled", result)
        assertTrue(run.cancelled.get())
    }

    @Test fun cancelledBeforeStartNeverStarts() {
        val run = FakeRun(finishAfterPolls = 0, success = true, out = "")
        val runner = runnerOf(run)
        val result = runCancellable(runner, arrayOf("x"), { true }, pollMs = 1)
        assertEquals(false to "cancelled", result)
        assertEquals(null, runner.lastArgs)
    }

    @Test fun buildConfigAliasMatchesApp() {
        assertEquals(xyz.losslessmusic.app.BuildConfig.APPLICATION_ID, com.zarz.spotiflac.BuildConfig.APPLICATION_ID)
    }
}
