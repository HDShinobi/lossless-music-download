package xyz.losslessmusic.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

object DlnaThumbnailer {
    fun write(src: File, dst: File, maxPx: Int): Boolean {
        return try {
            if (maxPx <= 0) return false
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(src.absolutePath, options)
            if (options.outWidth <= 0 || options.outHeight <= 0) return false
            val longEdge = maxOf(options.outWidth, options.outHeight)
            var sampleSize = 1
            while (longEdge / (sampleSize.toLong() * 2) >= maxPx) sampleSize *= 2
            options.inJustDecodeBounds = false
            options.inSampleSize = sampleSize
            val decoded = BitmapFactory.decodeFile(src.absolutePath, options) ?: return false
            var scaled: Bitmap? = null
            try {
                val decodedLongEdge = maxOf(decoded.width, decoded.height)
                val output = if (decodedLongEdge > maxPx) {
                    val width = maxOf(1, (decoded.width.toLong() * maxPx / decodedLongEdge).toInt())
                    val height = maxOf(1, (decoded.height.toLong() * maxPx / decodedLongEdge).toInt())
                    Bitmap.createScaledBitmap(decoded, width, height, true).also { scaled = it }
                } else decoded
                dst.outputStream().use { output.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            } finally {
                if (scaled !== decoded) scaled?.recycle()
                decoded.recycle()
            }
        } catch (_: Throwable) {
            // Includes decode allocation failures; callers can serve the original cover.
            false
        }
    }
}
