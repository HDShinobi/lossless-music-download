import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ffmpeg_metadata_service.dart';
import '../services/app_log.dart';
import '../vendor/spotiflac/convert_service.dart';
import '../services/library_re_enrich.dart';
import 'download_options_provider.dart';
import 'download_history_provider.dart';
import 'extensions_provider.dart';
import 'library_provider.dart';
import 'library_busy_provider.dart';

/// Admission failed before any file or history mutation.
class LibraryBusyException implements Exception {}

/// Builds the lowercase-keyed field map expected by the backend's
/// `EditFileMetadata`, dropping empty/whitespace values and trimming the rest.
/// Pure and unit-tested.
Map<String, String> buildEditFields({
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  String? year,
  String? genre,
  String? trackNumber,
}) {
  final out = <String, String>{};
  void put(String key, String? value) {
    final v = value?.trim() ?? '';
    if (v.isNotEmpty) out[key] = v;
  }

  put('title', title);
  put('artist', artist);
  put('album', album);
  put('album_artist', albumArtist);
  put('date', year);
  put('genre', genre);
  put('track_number', trackNumber);
  return out;
}

/// Maps the lowercase edit-field keys to the UPPERCASE keys the Dart FFmpeg
/// tagger uses (for lossy formats the Go backend hands back to us).
Map<String, String> editFieldsToFfmpeg(Map<String, String> fields) {
  const keyMap = {
    'title': 'TITLE',
    'artist': 'ARTIST',
    'album': 'ALBUM',
    'album_artist': 'ALBUMARTIST',
    'date': 'DATE',
    'genre': 'GENRE',
    'track_number': 'TRACKNUMBER',
  };
  final out = <String, String>{};
  fields.forEach((k, v) {
    final mapped = keyMap[k];
    if (mapped != null) out[mapped] = v;
  });
  return out;
}

/// Mutating operations on the local library: delete a file, edit its tags, and
/// re-enrich it. Each operation re-resolves [libraryProvider] so the list and
/// any open detail view refresh.
class LibraryManager extends Notifier<void> {
  @override
  void build() {}

  /// Exclusive with batch re-enrich and reorganize; with the download queue
  /// only when it is writing [path] itself.
  Future<T> _mutate<T>(String? path, Future<T> Function() action) async {
    final running = ref.read(libraryReorganizeRunningProvider.notifier);
    if (!running.tryStart(ignoreQueue: true)) throw LibraryBusyException();
    try {
      if (path != null && await isActiveLibraryDownloadPath(ref, path)) {
        throw LibraryBusyException();
      }
      return await action();
    } finally {
      running.finish();
    }
  }

  /// Deletes the file at [path] from disk (no-op if missing) and refreshes the
  /// library.
  Future<void> delete(String path) => _mutate(path, () async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    ref.invalidate(libraryProvider);
  });

  /// Writes [fields] (lowercase keys, e.g. from [buildEditFields]) into the file
  /// at [path]. FLAC/WAV/AIFF/APE are tagged natively by the Go backend; lossy
  /// formats (MP3/Opus/M4A) are finished via the Dart FFmpeg tagger. Refreshes
  /// the library afterwards.
  Future<void> editMetadata(
    String path,
    Map<String, String> fields,
  ) => _mutate(path, () async {
    final bridge = ref.read(backendBridgeProvider);
    final result = await bridge.editFileMetadata(path, fields);

    if ((result['method'] ?? '').toString() == 'ffmpeg') {
      // Lossy format: the backend returned the (possibly merged) fields for the
      // Dart FFmpeg path to write.
      final raw = result['fields'];
      final merged = raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : fields;
      await FfmpegMetadataService.embed(
        filePath: path,
        metadata: editFieldsToFfmpeg(merged),
      );
    }
    ref.invalidate(libraryProvider);
  });

  /// Converts the file at [path] to [format]/[bitrate] (FFmpeg), deletes the
  /// original on success, and refreshes the library. Returns the new file path,
  /// or null on failure.
  Future<String?> convert(String path, String format, String bitrate) =>
      _mutate(path, () async {
        final newPath = await ConvertService.convert(
          inputPath: path,
          format: format,
          bitrate: bitrate,
        );
        if (newPath == null) return null;
        if (newPath != path) {
          final original = File(path);
          if (await original.exists()) await original.delete();
        }
        ref.invalidate(libraryProvider);
        return newPath;
      });

  Future<ReEnrichOptions> reEnrichOptions() async {
    await Future.wait([
      ref.read(embedCoverProvider.notifier).ready,
      ref.read(embedLyricsProvider.notifier).ready,
      ref.read(writeLrcSidecarProvider.notifier).ready,
      ref.read(artistTagModeProvider.notifier).ready,
      ref.read(metadataSeparatorsProvider.notifier).ready,
    ]);
    final embedLyrics = ref.read(embedLyricsProvider);
    final sidecar = ref.read(writeLrcSidecarProvider);
    return ReEnrichOptions(
      embedCover: ref.read(embedCoverProvider),
      // Rust's embed_lyrics flag enables fetching; lyrics_mode controls where
      // the result is written. A sidecar-only refresh must still fetch lyrics.
      embedLyrics: embedLyrics || sidecar,
      lyricsMode: sidecar ? (embedLyrics ? 'both' : 'external') : 'embed',
      artistTagMode: ref.read(artistTagModeProvider),
      separators: ref.read(metadataSeparatorsProvider),
    );
  }

  Future<Map<String, dynamic>> reEnrichEntry(
    LibraryEntry entry, {
    ReEnrichOptions? options,
    bool refreshLibrary = true,
    bool inBatch = false,
  }) {
    // Batch admission already owns the shared busy state for its entire run.
    if (inBatch) return _reEnrichEntry(entry, options, refreshLibrary);
    return _mutate(entry.path, () => _reEnrichEntry(entry, options, refreshLibrary));
  }

  Future<Map<String, dynamic>> _reEnrichEntry(
    LibraryEntry entry,
    ReEnrichOptions? options,
    bool refreshLibrary,
  ) async {
    try {
      late Map<String, dynamic> result;
      Object? finishingError;
      try {
        result = await reEnrichLibraryEntry(
          ref.read(backendBridgeProvider),
          entry,
          options ?? await reEnrichOptions(),
        );
      } on ReEnrichPartialFailure catch (e) {
        result = e.result;
        finishingError = e.cause;
      }
      try {
        final history = await ref.read(historyDatabaseProvider.future);
        await history.updateReEnriched(entry.path, result);
        ref.read(historyRevisionProvider.notifier).changed();
      } catch (e) {
        printAppLog(
          LogLevel.warning,
          'Library',
          'Re-enrich history update failed; path=${entry.path}; $e',
        );
      }
      await writeReEnrichSidecar(entry.path, result);
      if (finishingError != null) throw finishingError;
      return result;
    } finally {
      if (entry.coverPath != null) {
        await FileImage(File(entry.coverPath!)).evict();
      }
      if (ref.mounted && refreshLibrary) ref.invalidate(libraryProvider);
    }
  }

  /// Re-fetches metadata/cover/lyrics for [request] (backend reEnrichRequest
  /// shape) and refreshes the library.
  Future<Map<String, dynamic>> reEnrich(Map<String, dynamic> request) =>
      _mutate(null, () async {
        final bridge = ref.read(backendBridgeProvider);
        final result = await bridge.reEnrichFile(request);
        ref.invalidate(libraryProvider);
        return result;
      });
}

final libraryManagerProvider = NotifierProvider<LibraryManager, void>(
  LibraryManager.new,
);
