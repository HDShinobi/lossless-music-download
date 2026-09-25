package xyz.losslessmusic.app.engine

import java.util.concurrent.atomic.AtomicBoolean

/** Holds the debug probe inputs until Go has finished loading its extension directory. */
internal class RustProbeStartGate {
    @Volatile private var key: String? = null
    @Volatile private var dirs: Pair<String, String>? = null
    private val started = AtomicBoolean(false)

    fun captureKey(masterKey: String) {
        key = masterKey
    }

    fun captureDirs(extDir: String, dataDir: String) {
        dirs = extDir to dataDir
    }

    fun afterLoad(debug: Boolean, start: (String, String, String) -> Unit) {
        if (!debug) return
        val masterKey = key ?: return
        val (extDir, dataDir) = dirs ?: return
        if (started.compareAndSet(false, true)) start(extDir, dataDir, masterKey)
    }
}
