package xyz.losslessmusic.app.engine

import java.io.File
import java.util.UUID

/**
 * Spec §3.4: until the phase-5 cutover the Rust engine never writes the Go engine's data dirs.
 * It works on a one-time copy under `<support>/engine-rust/`, published by atomic rename so an
 * interrupted copy is never mistaken for a complete one.
 */
object EngineDataIsolation {
    const val ROOT_NAME = "engine-rust"
    private const val TMP_PREFIX = "$ROOT_NAME.tmp-"

    data class Dirs(val extensions: File, val data: File)

    fun ensureRustCopy(goExtDir: File, goDataDir: File): Dirs {
        val parent = requireNotNull(goExtDir.absoluteFile.parentFile) { "extension dir has no parent" }
        val root = File(parent, ROOT_NAME)
        val dirs = Dirs(File(root, goExtDir.name), File(root, goDataDir.name))
        parent.listFiles { f -> f.name.startsWith(TMP_PREFIX) }?.forEach { it.deleteRecursively() }
        if (!root.isDirectory) {
            val staging = File(parent, "$TMP_PREFIX${UUID.randomUUID()}")
            try {
                copyOrCreate(goExtDir, File(staging, goExtDir.name))
                copyOrCreate(goDataDir, File(staging, goDataDir.name))
                check(staging.renameTo(root)) { "failed to publish $root" }
            } finally {
                if (staging.exists()) staging.deleteRecursively()
            }
        }
        dirs.extensions.mkdirs()
        dirs.data.mkdirs()
        return dirs
    }

    private fun copyOrCreate(source: File, target: File) {
        if (source.isDirectory) {
            source.copyRecursively(target, overwrite = false)
        } else {
            check(target.mkdirs()) { "failed to create $target" }
        }
    }
}
