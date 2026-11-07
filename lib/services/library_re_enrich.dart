import 'dart:io';

import '../models/library_entry.dart';
import '../models/metadata_separators.dart';
import 'backend_bridge.dart';
import 'download_paths.dart';
import 'ffmpeg_metadata_service.dart';

/// Immutable settings for one batch; default dimensions/mode match upstream.
class ReEnrichOptions {
  const ReEnrichOptions({
    this.embedCover = true,
    this.embedLyrics = true,
    this.lyricsMode = 'embed',
    this.artistTagMode = 'joined',
    this.separators = const MetadataSeparators(),
  });
  final bool embedCover, embedLyrics;
  final String lyricsMode, artistTagMode;
  final MetadataSeparators separators;

  Map<String, dynamic> request(LibraryEntry entry) => {
    'file_path': entry.path,
    'track_name':
        entry.title ??
        stripTrackNumberPrefix(
          entry.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        ),
    'artist_name': entry.artistName ?? '',
    'album_name': entry.albumName ?? '',
    'album_artist': entry.albumArtist ?? '',
    'track_number': entry.trackNumber ?? 0,
    'disc_number': entry.discNumber ?? 0,
    'total_tracks': entry.totalTracks ?? 0,
    'total_discs': entry.totalDiscs ?? 0,
    'release_date': entry.releaseDate ?? '',
    'isrc': entry.isrc ?? '',
    'genre': entry.genre ?? '',
    'composer': entry.composer ?? '',
    'label': entry.label ?? '',
    'copyright': entry.copyright ?? '',
    'duration_ms': entry.durationMs ?? 0,
    'spotify_id': '',
    'cover_url': '',
    'cover_max_dimension': 0,
    'embed_lyrics': embedLyrics,
    'lyrics_mode': lyricsMode,
    'artist_tag_mode': artistTagMode,
    'metadata_separators': separators.toJson(),
    'search_online': true,
    'replace_release_metadata': false,
    'update_fields': [
      'basic_tags',
      'track_info',
      'release_info',
      'extra',
      if (embedCover) 'cover',
      if (embedLyrics) 'lyrics',
    ],
  };

  Map<String, dynamic> formatMetadata(Map raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final key in ['artist_name', 'album_artist']) {
      if (artistTagMode == 'primary' && out[key] is String) {
        out[key] = (out[key] as String)
            .split(
              RegExp(
                r'\s*[,;&]\s*|\s+x\s+|\s+(?:feat(?:uring|ured|ure)?|ft|with)\.?(?:\s+|$)',
                caseSensitive: false,
              ),
            )
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      }
    }
    for (final pair in [
      ('artist_name', separators.artist),
      ('album_artist', separators.albumArtist),
      ('composer', separators.composer),
      ('genre', separators.genre),
    ]) {
      final value = out[pair.$1];
      if (pair.$2.isNotEmpty && value is String) {
        out[pair.$1] = value
            .split(RegExp(r'[,;]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(pair.$2);
      }
    }
    return out;
  }
}

/// The audio was written before an optional finishing step failed. Callers
/// still publish its metadata to history, then report the per-file failure.
class ReEnrichPartialFailure implements Exception {
  const ReEnrichPartialFailure(this.result, this.cause);
  final Map<String, dynamic> result;
  final Object cause;
  @override
  String toString() => cause.toString();
}

/// Resolve online first, then apply those exact values. Rust re-enrichment does
/// not parse separators, so format the resolved tags before sending the write.
Future<Map<String, dynamic>> reEnrichLibraryEntry(
  BackendBridge bridge,
  LibraryEntry entry,
  ReEnrichOptions options,
) async {
  final request = options.request(entry);
  final preview = await bridge.reEnrichFile({...request, 'preview_only': true});
  if (preview['method'] != 'preview' ||
      preview['enriched_metadata'] is! Map ||
      preview['success'] == false) {
    throw StateError('${preview['error'] ?? 'Metadata lookup failed'}');
  }
  final result = await bridge.reEnrichFile({
    ...request,
    ...options.formatMetadata(preview['enriched_metadata'] as Map),
    'file_path': entry.path,
    'search_online': false,
  });
  if (result['success'] == false ||
      !['native', 'ffmpeg'].contains(result['method'])) {
    throw StateError('${result['error'] ?? 'Metadata write failed'}');
  }
  if (result['method'] == 'ffmpeg') {
    await applyReEnrichFfmpeg(
      entry.path,
      result,
      options.artistTagMode,
      options.separators,
    );
  }
  // Re-enrich's Rust Request omits separator controls, while the existing tag
  // editor accepts them. Restore only custom joined credits after native split
  // mode; the other artist field retains the native repeated values.
  if (result['method'] == 'native' &&
      entry.path.toLowerCase().endsWith('.flac') &&
      options.artistTagMode == 'split_vorbis') {
    final metadata = options.formatMetadata(
      preview['enriched_metadata'] as Map,
    );
    final fields = <String, String>{};
    for (final pair in [
      ('artist_name', 'artist', options.separators.artist),
      ('album_artist', 'album_artist', options.separators.albumArtist),
    ]) {
      final value = metadata[pair.$1];
      if (pair.$3.isNotEmpty && value is String && value.isNotEmpty) {
        fields[pair.$2] = value;
        fields['${pair.$2}_separator'] = pair.$3;
      }
    }
    if (fields.isNotEmpty) {
      fields['artist_tag_mode'] = options.artistTagMode;
      try {
        final edited = await bridge.editFileMetadata(entry.path, fields);
        if (edited['success'] != true || edited['method'] != 'native') {
          throw StateError('${edited['error'] ?? 'Artist tag write failed'}');
        }
      } catch (e) {
        throw ReEnrichPartialFailure(result, e);
      }
    }
  }
  return result;
}

Future<void> writeReEnrichSidecar(
  String originalPath,
  Map<String, dynamic> result,
) async {
  final returnedPath = result['file_path'] as String?;
  final path = returnedPath == null || returnedPath.isEmpty
      ? originalPath
      : returnedPath;
  if (result['write_external_lrc'] == true &&
      result['lyrics'] is String &&
      (result['lyrics'] as String).trim().isNotEmpty) {
    await File(
      path.replaceFirst(RegExp(r'\.[^./]+$'), '.lrc'),
    ).writeAsString(result['lyrics'] as String);
  }
}
