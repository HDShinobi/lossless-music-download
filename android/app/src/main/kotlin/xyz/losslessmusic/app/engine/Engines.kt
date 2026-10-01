package xyz.losslessmusic.app.engine

import android.content.Context
import android.util.Log
import java.io.File

/** Process-scoped Rust engine holder: initialized once for the process lifetime. */
object Engines {
    @Volatile private var engine: NativeEngine? = null

    fun init(context: Context) {
        if (engine != null) return
        synchronized(this) {
            if (engine != null) return
            val files = context.applicationContext.filesDir
            engine = build(files) { Log.i("RustEngine", it) }
            Log.i("Engines", "engine=RUST")
        }
    }

    internal fun build(filesDir: File, log: (String) -> Unit): NativeEngine =
        RustEngine(UniffiRustCore.FACTORY, filesDir, log = log)

    val current: NativeEngine
        get() = engine ?: error("Engines.init(context) must run before the engine is used")
}
