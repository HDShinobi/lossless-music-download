package xyz.losslessmusic.app.engine

import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.util.Locale

/** Corrects Rust's fallback .flac name when an extension wrote a different container. */
object ContainerExtensionFix {
    fun apply(result: JSONObject, log: (String) -> Unit): JSONObject {
        if (!result.optBoolean("success", false) || result.optBoolean("already_exists", false)) return result
        val path = result.optString("file_path", "")
        if (!path.endsWith(".flac", ignoreCase = true)) return result
        val source = File(path)
        if (!source.isFile) return result

        try {
            val header = ByteArray(12)
            val count = source.inputStream().use { stream ->
                var read = 0
                while (read < header.size) {
                    val n = stream.read(header, read, header.size - read)
                    if (n < 0) break
                    read += n
                }
                read
            }
            val ext = when {
                count >= 4 && header.startsWithAscii("fLaC") -> return result
                count >= 8 && header.hasAsciiAt(4, "ftyp") -> {
                    if (result.optString("audio_codec", "").lowercase(Locale.ROOT) in setOf("ac4", "ac-4")) ".mp4" else ".m4a"
                }
                count >= 4 && header.startsWithAscii("OggS") -> ".opus"
                count >= 3 && header.startsWithAscii("ID3") -> {
                    if (count >= 10 && source.hasFlacAfterId3(header)) return result
                    ".mp3"
                }
                count >= 2 && header[0] == 0xff.toByte() &&
                    (header[1].toInt() and 0xf6) == 0xf0 -> ".aac"
                count >= 2 && header[0] == 0xff.toByte() &&
                    (header[1].toInt() and 0xe0) == 0xe0 &&
                    (header[1].toInt() and 0x06) != 0 -> ".mp3"
                else -> return result
            }

            val base = source.name.dropLast(5)
            var suffix = 1
            while (true) {
                val name = if (suffix == 1) "$base$ext" else "$base ($suffix)$ext"
                val target = File(source.parentFile, name)
                if (target.exists()) {
                    suffix++
                    continue
                }
                try {
                    Files.move(source.toPath(), target.toPath())
                } catch (_: FileAlreadyExistsException) {
                    suffix++
                    continue
                }
                result.put("file_path", target.path)
                if (result.has("actual_extension")) result.put("actual_extension", ext)
                if (result.has("output_extension")) result.put("output_extension", ext)
                if (result.has("resolved_file_name")) result.put("resolved_file_name", name)
                log("download container extension: ${source.name} -> $name")
                return result
            }
        } catch (e: Exception) {
            log("download container extension: ${e.message ?: e.javaClass.simpleName}")
            return result
        }
    }

    private fun ByteArray.startsWithAscii(value: String) = hasAsciiAt(0, value)

    private fun File.hasFlacAfterId3(header: ByteArray): Boolean {
        val tagSize = (6..9).fold(0L) { size, index ->
            (size shl 7) or (header[index].toLong() and 0x7f)
        }
        val offset = 10L + tagSize + if ((header[5].toInt() and 0x10) != 0) 10L else 0L
        RandomAccessFile(this, "r").use { file ->
            if (file.length() < offset + 4) return false
            file.seek(offset)
            val next = ByteArray(4)
            file.readFully(next)
            return next.startsWithAscii("fLaC")
        }
    }

    private fun ByteArray.hasAsciiAt(offset: Int, value: String): Boolean =
        value.indices.all { this[offset + it] == value[it].code.toByte() }
}
