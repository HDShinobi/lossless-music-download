package xyz.losslessmusic.app.engine

import com.spotiflac.backend.ExtensionManager
import org.json.JSONObject
import java.io.File

/**
 * Phase-1 debug probe (spec §3.5): can the Rust engine read a real v0.9.1 (Go-era) extension
 * profile? Runs only on the isolated engine-rust copy (§3.4), never on the Go dirs, and never
 * throws — the app keeps running on Go whatever happens here.
 */
object RustEngineProbe {
    const val FLAG_FILE = "debug_rust_probe"
    const val RESULT_FILE = "rust_probe.json"
    private const val TIMEOUT_MS: ULong = 30_000uL

    fun run(goExtDir: File, goDataDir: File, masterKey: String): JSONObject {
        val result = JSONObject().put("engine_version", EngineVersion.SPOTIFLAC_ENGINE_VERSION)
        return try {
            val dirs = EngineDataIsolation.ensureRustCopy(goExtDir, goDataDir)
            val manager = ExtensionManager.withLyricsSettings(
                dirs.extensions.canonicalPath,
                dirs.data.canonicalPath,
                masterKey,
                EngineVersion.SPOTIFLAC_ENGINE_VERSION,
                TIMEOUT_MS,
                "[]",
                "{}",
            )
            try {
                result.put("load_all", manager.loadAll())
                    .put("installed", manager.installed())
                    .put("provider_priorities", manager.providerPriorities())
                    .put("ok", true)
            } finally {
                manager.shutdown()
                manager.close()
            }
        } catch (error: Throwable) {
            result.put("ok", false).put("error", "${error.javaClass.simpleName}: ${error.message}")
        }
    }

    /** Runs [run] only when `<filesDir>/debug_rust_probe` exists; writes `<filesDir>/rust_probe.json`. */
    fun runIfRequested(filesDir: File, goExtDir: File, goDataDir: File, masterKey: String): Boolean {
        if (!File(filesDir, FLAG_FILE).exists()) return false
        File(filesDir, RESULT_FILE).writeText(run(goExtDir, goDataDir, masterKey).toString(2))
        return true
    }
}
