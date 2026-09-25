// LM-OWNED shims (not upstream). The vendored com/zarz/spotiflac/CoreBackend.kt references
// NativeDownloadFinalizer.runFFmpegArguments and BuildConfig.APPLICATION_ID from upstream's
// package; these declarations satisfy that contract with our own ffmpeg-kit and app id, so
// CoreBackend.kt stays byte-identical to upstream. Registered in docs/UPSTREAM-SYNC.md.
package com.zarz.spotiflac

import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import java.util.concurrent.CountDownLatch

internal object BuildConfig {
    const val APPLICATION_ID: String = xyz.losslessmusic.app.BuildConfig.APPLICATION_ID
}

internal interface RunningFFmpeg {
    fun isDone(): Boolean
    fun succeeded(): Boolean
    fun output(): String
    fun cancel()
}

internal interface FFmpegRunner {
    fun start(arguments: Array<String>): RunningFFmpeg
}

internal fun runCancellable(
    runner: FFmpegRunner,
    arguments: Array<String>,
    shouldCancel: () -> Boolean,
    pollMs: Long = 50,
): Pair<Boolean, String> {
    if (shouldCancel()) return false to "cancelled"
    val run = runner.start(arguments)
    while (!run.isDone()) {
        if (shouldCancel()) {
            run.cancel()
            return false to "cancelled"
        }
        Thread.sleep(pollMs)
    }
    return if (run.succeeded()) true to run.output() else false to run.output().ifBlank { "FFmpeg failed" }
}

private object FFmpegKitRunner : FFmpegRunner {
    override fun start(arguments: Array<String>): RunningFFmpeg {
        val done = CountDownLatch(1)
        val session = FFmpegKit.executeWithArgumentsAsync(arguments) { done.countDown() }
        return object : RunningFFmpeg {
            override fun isDone() = done.count == 0L
            override fun succeeded() = ReturnCode.isSuccess(session.returnCode)
            override fun output(): String = session.output ?: ""
            override fun cancel() = FFmpegKit.cancel(session.sessionId)
        }
    }
}

internal object NativeDownloadFinalizer {
    @Volatile
    internal var runner: FFmpegRunner = FFmpegKitRunner

    /** Same call shape as upstream's extension fun; [trackFinalizerSession] is upstream-only bookkeeping. */
    @Suppress("UNUSED_PARAMETER")
    fun runFFmpegArguments(
        arguments: Array<String>,
        shouldCancel: () -> Boolean = { false },
        trackFinalizerSession: Boolean = true,
    ): Pair<Boolean, String> = runCancellable(runner, arguments, shouldCancel)
}
