import '../models/track.dart';
import 'download_paths.dart';

/// The engine's unformatted placeholders, plus bounded numeric padding.
/// Folder templates are expanded here, one segment at a time: the engine's
/// album_folder_template only substitutes {album} and can re-parent output_dir.
abstract final class DownloadTemplates {
  static const placeholders = [
    'title',
    'artist',
    'album',
    'track',
    'track_raw',
    'disc',
    'disc_raw',
    'playlist_position',
    'playlist position',
    'playlistPosition',
    'position',
    'playlist_position_raw',
    'year',
    'date',
    'quality',
    'quality_variant',
    'isrc',
    'provider',
    'platform',
    'provider_id',
    'id',
  ];
  static const filenamePresets = [
    '{track}. {title}',
    '{artist} - {title}',
    '{title} - {artist}',
    '{disc}-{track}. {title}',
  ];
  static const folderPresets = [
    '{artist}/{album}',
    '{artist}/{album} ({year})',
    '{album}',
    '{year} - {album}',
  ];
  static final _token = RegExp(r'\{([^{}]+)\}');
  static final _number = RegExp(
    r'^(track|disc|playlist_position|playlistPosition|position):0?[1-9]$',
  );

  /// Returns a stable error code for the localized editor. Null is valid.
  /// Limit padding to nine digits and templates to 1024 characters.
  static String? validate(String template, {bool folder = false}) {
    if (template.trim().isEmpty ||
        template.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(template)) {
      return 'empty';
    }
    if (!folder && RegExp(r'[/\\]').hasMatch(template)) return 'path';
    final literals = template.replaceAllMapped(_token, (m) {
      return placeholders.contains(m[1]) || _number.hasMatch(m[1]!)
          ? ''
          : m[0]!;
    });
    if (literals.contains('{') || literals.contains('}')) return 'placeholder';
    final parts = folder ? template.split(RegExp(r'[/\\]')) : [template];
    if (parts.length > 16 ||
        parts.any(
          (p) => p.trim().isEmpty || p.trim() == '.' || p.trim() == '..',
        ) ||
        (folder && RegExp(r'^[a-zA-Z]:').hasMatch(template))) {
      return 'path';
    }
    for (final part in parts) {
      final rendered = _expand(part, sample(), quality: 'LOSSLESS');
      if (_usable(rendered).isEmpty) return 'empty';
    }
    return null;
  }

  static Track sample({bool multiDisc = false}) => Track(
    id: 'qobuz:123',
    name: 'Sample Song',
    artists: 'Sample Artist',
    albumName: 'Sample Album',
    albumArtist: 'Sample Artist',
    trackNumber: 3,
    discNumber: multiDisc ? 2 : 1,
    totalDiscs: multiDisc ? 2 : 1,
    releaseDate: '2026-11-07',
    isrc: 'USABC2600001',
    source: 'qobuz',
    playlistPosition: 5,
  );

  static String preview(String template, Track track, {String? quality}) =>
      sanitizeFolderSegment(_expand(template, track, quality: quality));

  static String folder(String template, Track track, {String? quality}) =>
      template
          .split(RegExp(r'[/\\]'))
          .map((part) => preview(part, track, quality: quality))
          .join('/');

  static String _usable(String value) => value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]'), ' ')
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');

  static String _expand(String template, Track track, {String? quality}) {
    String number(int? value, int width) =>
        (value ?? 0) > 0 ? value.toString().padLeft(width, '0') : '';
    final date = track.releaseDate?.trim() ?? '';
    final providerId = track.id.contains(':')
        ? track.id.substring(track.id.indexOf(':') + 1)
        : '';
    final values = <String, String>{
      'title': track.name.trim(),
      'artist': track.artists.trim(),
      'album': track.albumName?.trim() ?? '',
      'track': number(track.trackNumber, 2),
      'track_raw': number(track.trackNumber, 1),
      'disc': number(track.discNumber, 1),
      'disc_raw': number(track.discNumber, 1),
      for (final key in [
        'playlist_position',
        'playlist position',
        'playlistPosition',
        'position',
      ])
        key: number(track.playlistPosition, 2),
      'playlist_position_raw': number(track.playlistPosition, 1),
      'date': date,
      'year': date.length >= 4 ? date.substring(0, 4) : '',
      'isrc': track.isrc?.trim() ?? '',
      'provider': track.source?.trim() ?? '',
      'platform': track.source?.trim() ?? '',
      'provider_id': providerId,
      'id': providerId,
      'quality': quality ?? '',
      'quality_variant': '',
    };
    var result = template.replaceAllMapped(_token, (m) {
      final key = m[1]!;
      if (_number.hasMatch(key)) {
        final name = key.split(':').first;
        final value = switch (name) {
          'track' => track.trackNumber,
          'disc' => track.discNumber,
          _ => track.playlistPosition,
        };
        return number(value, int.parse(key.split(':').last));
      }
      return values[key] ?? '';
    });
    // Mirror engine cleanup when optional provider identifiers are absent.
    if ([
      'isrc',
      'provider',
      'platform',
      'provider_id',
      'id',
    ].any((key) => template.contains('{$key}') && values[key]!.isEmpty)) {
      result = result
          .replaceAll(RegExp(r'\[\s*\]|\(\s*\)'), '')
          .replaceAllMapped(RegExp(r'\s*[-_|]\s*([\]\)])'), (m) => m[1]!)
          .replaceAll(RegExp(r'\s*[-–—_|]\s*(?:[-–—_|]\s*)+'), ' - ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[ \-–—_|]+|[ \-–—_|]+$'), '');
    }
    return result;
  }
}

/// Shared by preview, native requests and the Dart ISRC pre-check. Empty
/// preferences preserve every legacy folder and filename default.
({String dir, String template}) resolveDownloadTarget(
  String baseDir,
  Track track, {
  required FolderOrganization mode,
  String filenameTemplate = '',
  String albumFolderTemplate = '',
  String? quality,
}) {
  final custom =
      filenameTemplate.isNotEmpty &&
      DownloadTemplates.validate(filenameTemplate) == null;
  var basename = custom
      ? filenameTemplate
      : basenameTemplateFor(
          mode,
          discNumber: track.discNumber,
          totalDiscs: track.totalDiscs,
        );
  final multiDisc =
      (track.totalDiscs ?? 0) > 1 ||
      ((track.totalDiscs ?? 0) <= 0 && (track.discNumber ?? 0) > 1);
  // Include raw and padded disc tokens; never add the disc twice.
  if (custom &&
      multiDisc &&
      !RegExp(r'\{disc(?::0?[1-9]|_raw)?\}').hasMatch(basename)) {
    basename = '{disc}-$basename';
  }
  final date = track.releaseDate?.trim() ?? '';
  final template = pruneEmptyPlaceholders(basename, {
    'artist': track.artists,
    'title': track.name,
    'album': track.albumName ?? '',
    'track': track.trackNumber?.toString() ?? '',
    'disc': (track.discNumber ?? 0) > 0 ? '${track.discNumber}' : '',
    'year': date.length >= 4 ? date.substring(0, 4) : '',
  });
  final relative =
      albumFolderTemplate.isNotEmpty &&
          DownloadTemplates.validate(albumFolderTemplate, folder: true) == null
      ? DownloadTemplates.folder(albumFolderTemplate, track, quality: quality)
      : buildRelativeFolder(
          mode,
          FolderMetadata(
            artist: track.artists,
            albumArtist: track.albumArtist,
            album: track.albumName,
          ),
        );
  return (
    dir: relative.isEmpty
        ? baseDir
        : '${baseDir.replaceAll(RegExp(r'/+$'), '')}/$relative',
    template: template,
  );
}
