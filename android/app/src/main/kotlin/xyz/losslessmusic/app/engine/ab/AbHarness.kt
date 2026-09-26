package xyz.losslessmusic.app.engine.ab

import org.json.JSONArray
import org.json.JSONObject
import xyz.losslessmusic.app.engine.EngineKind
import xyz.losslessmusic.app.engine.NativeEngine
import java.io.File

/** Debug-only A/B parity harness driven by flag files in filesDir (see scripts/ab-parity.sh). */
object AbHarness {
    const val CAPTURE_FLAG = "ab_capture"
    const val RESTORE_FLAG = "ab_restore"
    const val RECORD_FLAG = "ab_record"
    const val COMPARE_FLAG = "ab_compare"
    const val FIXTURE_DIR = "ab-fixture"
    const val SAMPLE_URL = "https://open.spotify.com/track/0DiWol3AO6WpXZgp0goxAV"
    private val GO_DIRS = listOf("extensions", "ext_data")

    fun onProcessStart(filesDir: File, log: (String) -> Unit) {
        val fixture = File(filesDir, FIXTURE_DIR)
        consume(filesDir, CAPTURE_FLAG) {
            fixture.deleteRecursively()
            GO_DIRS.forEach { copyOrCreate(File(filesDir, it), File(fixture, it)) }
            log("ab: fixture captured")
        }
        consume(filesDir, RESTORE_FLAG) {
            if (!fixture.isDirectory) { log("ab: no fixture to restore"); return@consume }
            GO_DIRS.forEach { File(filesDir, it).deleteRecursively() }
            File(filesDir, "engine-rust").deleteRecursively()
            GO_DIRS.forEach { copyOrCreate(File(fixture, it), File(filesDir, it)) }
            log("ab: fixture restored")
        }
        consume(filesDir, COMPARE_FLAG) {
            val go = File(filesDir, "ab-go.json"); val rust = File(filesDir, "ab-rust.json")
            if (!go.exists() || !rust.exists()) { log("ab: compare needs ab-go.json and ab-rust.json"); return@consume }
            File(filesDir, "ab-diff.json").writeText(compare(JSONObject(go.readText()), JSONObject(rust.readText())).toString(2))
            log("ab: diff written")
        }
    }

    fun recordIfRequested(filesDir: File, musicDir: File, engine: NativeEngine): Boolean {
        val flag = File(filesDir, RECORD_FLAG)
        if (!flag.exists()) return false
        val name = if (engine.kind == EngineKind.RUST) "ab-rust.json" else "ab-go.json"
        File(filesDir, name).writeText(record(engine, musicDir).toString(2))
        flag.delete()
        return true
    }

    fun record(engine: NativeEngine, musicDir: File): JSONObject {
        val out = JSONObject()
        fun step(name: String, call: () -> String) {
            out.put(name, try {
                JSONObject().put("ok", true).put("value", JsonShape.parse(call()) ?: JSONObject.NULL)
            } catch (e: Throwable) {
                JSONObject().put("ok", false).put("error", "${e.javaClass.simpleName}: ${e.message}")
            })
        }
        step("getInstalledExtensions") { engine.getInstalledExtensions() }
        val firstId = runCatching { JSONArray(engine.getInstalledExtensions()).getJSONObject(0).getString("id") }.getOrDefault("")
        step("getDownloadPriority") { engine.getDownloadPriority() }
        step("getMetadataPriority") { engine.getMetadataPriority() }
        step("getExtensionSettings") { engine.getExtensionSettings(firstId) }
        step("getExtensionPendingAuth") { engine.getExtensionPendingAuth(firstId) }
        step("findUrlHandler") { engine.findUrlHandler(SAMPLE_URL) }
        step("handleUrl") { engine.handleUrl(SAMPLE_URL) }
        step("searchTracks") { engine.searchTracks("daft punk one more time", 5, true) }
        step("getLyricsLRC") { engine.getLyricsLRC("", "One More Time", "Daft Punk", "", 320000) }
        step("checkDuplicate") { engine.checkDuplicate(musicDir.path, "GBDUW0000059") }
        step("scanLibraryFolder") { engine.scanLibraryFolder(musicDir.path) }
        val flac = musicDir.walkTopDown().firstOrNull { it.isFile && it.extension.equals("flac", true) }
        step("getAudioQuality") { flac?.let { engine.getAudioQuality(it.path) } ?: throw IllegalStateException("no flac in musicDir") }
        step("getAllDownloadProgress") { engine.getAllDownloadProgress() }
        return out
    }

    fun compare(go: JSONObject, rust: JSONObject): JSONObject {
        val result = JSONObject()
        var same = 0; var differs = 0; var errors = 0
        (go.keys().asSequence() + rust.keys().asSequence()).toSortedSet().forEach { name ->
            val g = go.optJSONObject(name); val r = rust.optJSONObject(name)
            val gOk = g?.optBoolean("ok") == true; val rOk = r?.optBoolean("ok") == true
            val entry = JSONObject()
            when {
                gOk && rOk -> {
                    val d = JsonShape.diff(JsonShape.of(g!!.opt("value")), JsonShape.of(r!!.opt("value")))
                    entry.put("status", if (d.isEmpty()) "same" else "differs").put("diffs", JSONArray(d))
                    if (d.isEmpty()) same++ else differs++
                }
                !gOk && !rOk -> { entry.put("status", "both_error"); errors++ }
                !gOk -> { entry.put("status", "go_error"); errors++ }
                else -> { entry.put("status", "rust_error"); errors++ }
            }
            g?.optString("error")?.takeIf { it.isNotEmpty() }?.let { entry.put("go_error", it) }
            r?.optString("error")?.takeIf { it.isNotEmpty() }?.let { entry.put("rust_error", it) }
            result.put(name, entry)
        }
        result.put("_summary", JSONObject().put("same", same).put("differs", differs).put("errors", errors))
        return result
    }

    private inline fun consume(filesDir: File, flag: String, action: () -> Unit) {
        val f = File(filesDir, flag)
        if (!f.exists()) return
        try { action() } finally { f.delete() }
    }

    private fun copyOrCreate(source: File, target: File) {
        if (source.isDirectory) source.copyRecursively(target, overwrite = true) else target.mkdirs()
    }
}
