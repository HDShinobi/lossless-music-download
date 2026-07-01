package xyz.losslessmusic.app

import android.content.Context

// TEMPORARY STUB for Task 5 build verification only.
// Task 6 replaces this with the real non-FLAC metadata embedding
// implementation (ID3/MP4 tag + cover art writer). Do not extend this file;
// it exists solely so DownloadForegroundService.kt compiles before Task 6
// lands.
object NonFlacMetadataEmbedder {
    fun isEmbeddable(path: String) = false
    fun embed(context: Context, filePath: String, requestJson: String) {}
}
