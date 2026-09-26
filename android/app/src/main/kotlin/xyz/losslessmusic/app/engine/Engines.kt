package xyz.losslessmusic.app.engine

import android.content.Context
import android.util.Log
import xyz.losslessmusic.app.BuildConfig
import java.io.File

/** Pure selection rule (spec §3.4, ruling R-P6). Read once per process. */
object EngineSelection {
    const val RUST_FLAG_FILE = "engine_rust"
    const val GO_FLAG_FILE = "engine_go"

    fun select(isDebug: Boolean, filesDir: File, debugDefault: EngineKind): EngineKind {
        if (!isDebug) return EngineKind.GO
        if (File(filesDir, GO_FLAG_FILE).exists()) return EngineKind.GO
        if (File(filesDir, RUST_FLAG_FILE).exists()) return EngineKind.RUST
        return debugDefault
    }
}

/** Process-scoped engine holder: chosen on the first init() and never changed for the process lifetime. */
object Engines {
    /** Debug-build default. Phase-2 exit flips this to RUST; release builds are always GO until phase 5. */
    val DEBUG_DEFAULT = EngineKind.GO

    @Volatile private var engine: NativeEngine? = null

    fun init(context: Context) {
        if (engine != null) return
        synchronized(this) {
            if (engine != null) return
            val files = context.applicationContext.filesDir
            val selected = EngineSelection.select(BuildConfig.DEBUG, files, DEBUG_DEFAULT)
            engine = build(selected, files)
            Log.i("Engines", "engine=${engine!!.kind} (selected=$selected)")
        }
    }

    private fun build(kind: EngineKind, filesDir: File): NativeEngine = when (kind) {
        EngineKind.GO -> GoEngine
        EngineKind.RUST -> RustEngine(UniffiRustCore.FACTORY, filesDir, log = { Log.i("RustEngine", it) })
    }

    val current: NativeEngine
        get() = engine ?: error("Engines.init(context) must run before the engine is used")

    val kind: EngineKind get() = current.kind
}
