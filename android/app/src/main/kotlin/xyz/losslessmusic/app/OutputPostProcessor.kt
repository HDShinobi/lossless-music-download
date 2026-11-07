package xyz.losslessmusic.app

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** Coordinates finalizers that may target the same published audio file. */
internal class OutputPostProcessor {
    // Keep locks for the service lifetime: removing one while it has waiters
    // could admit a third item on a different Mutex for the same path.
    private val locks = ConcurrentHashMap<String, Mutex>()

    suspend fun run(result: JSONObject, process: suspend () -> String): String {
        val path = result.optString("file_path", "")
        if (path.isEmpty()) return path
        return locks.computeIfAbsent(File(path).canonicalPath) { Mutex() }.withLock {
            if (result.optBoolean("already_exists", false)) path else process()
        }
    }
}
