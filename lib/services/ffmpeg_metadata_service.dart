import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Embeds tags + cover art + lyrics into NON-FLAC downloads (Opus / M4A / MP3)
/// using the bundled FFmpeg. FLAC is tagged natively in the Go backend, so this
/// service only runs as a fallback for lossy formats.
///
/// Ported from SpotiFLAC's FFmpegService (metadata-embed subset). Artist tags
/// use joined mode (matching our DownloadRequest default), so the split-artist
/// path is intentionally omitted.
///
/// The pure helpers (key mappers, argument builder, picture-block builder) are
/// `@visibleForTesting` so they can be unit-tested without invoking FFmpeg.
class FfmpegMetadataService {
  static int _tempCounter = 0;

  /// Returns true when [filePath] is a lossy format this service can tag.
  static bool isNonFlacEmbeddable(String filePath) {
    final ext = _extOf(filePath);
    return ext == 'opus' || ext == 'm4a' || ext == 'mp3' || ext == 'ogg';
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Embeds [metadata] (UPPERCASE Vorbis-style keys), optional [coverPath] and
  /// lyrics into the file at [filePath]. Returns true on success.
  static Future<bool> embed({
    required String filePath,
    required Map<String, String> metadata,
    String? coverPath,
  }) async {
    final ext = _extOf(filePath);
    switch (ext) {
      case 'opus':
      case 'ogg':
        return _embedOpus(filePath, metadata, coverPath);
      case 'm4a':
        return _embedM4a(filePath, metadata, coverPath);
      case 'mp3':
        return _embedMp3(filePath, metadata, coverPath);
      default:
        return false;
    }
  }

  // --- Per-format embed (download to temp, run FFmpeg, replace original) ---

  static Future<bool> _embedOpus(
    String opusPath,
    Map<String, String> metadata,
    String? coverPath,
  ) async {
    final tempOutput = await _nextTempPath('.opus');
    final args = <String>[
      '-v', 'error', '-hide_banner',
      '-i', opusPath,
      '-map', '0:a',
      '-map_metadata', '-1',
      '-map_metadata:s:a', '-1',
      '-c:a', 'copy',
    ];
    appendVorbisMetadataArgs(args, metadata);

    if (coverPath != null && await File(coverPath).exists()) {
      final block = await _coverPictureBase64(coverPath);
      if (block != null) {
        args
          ..add('-metadata')
          ..add('METADATA_BLOCK_PICTURE=$block');
      }
    }
    args..add(tempOutput)..add('-y');
    return _runAndReplace(args, tempOutput, opusPath, 'Opus');
  }

  static Future<bool> _embedM4a(
    String m4aPath,
    Map<String, String> metadata,
    String? coverPath,
  ) async {
    final tempOutput = await _nextTempPath('.m4a');
    final hasCover = coverPath != null && await File(coverPath).exists();
    final args = <String>['-v', 'error', '-hide_banner', '-i', m4aPath];
    if (hasCover) {
      args..add('-i')..add(coverPath);
    }
    // No cover replacement: keep all streams so existing art survives.
    args..add('-map')..add('0:a')..add('-c:a')..add('copy');
    args..add('-map_metadata')..add('-1');
    if (hasCover) {
      args
        ..add('-map')..add('1:v')
        ..add('-c:v')..add('copy')
        ..add('-disposition:v:0')..add('attached_pic')
        ..add('-metadata:s:v')..add('title=Album cover')
        ..add('-metadata:s:v')..add('comment=Cover (front)')
        // Force mp4 muxer: the default ipod muxer won't tag mjpeg on FFmpeg 8+.
        ..add('-f')..add('mp4');
    }
    appendMappedMetadataArgs(args, convertToM4aTags(metadata));
    args..add(tempOutput)..add('-y');
    return _runAndReplace(args, tempOutput, m4aPath, 'M4A');
  }

  static Future<bool> _embedMp3(
    String mp3Path,
    Map<String, String> metadata,
    String? coverPath,
  ) async {
    final tempOutput = await _nextTempPath('.mp3');
    final hasCover = coverPath != null && await File(coverPath).exists();
    final args = <String>['-v', 'error', '-hide_banner', '-i', mp3Path];
    if (hasCover) {
      args..add('-i')..add(coverPath);
    }
    args..add('-map')..add('0:a')..add('-map_metadata')..add('-1');
    if (hasCover) {
      args
        ..add('-map')..add('1:0')
        ..add('-c:v:0')..add('copy')
        ..add('-metadata:s:v')..add('title=Album cover')
        ..add('-metadata:s:v')..add('comment=Cover (front)');
    }
    args..add('-c:a')..add('copy');
    appendMappedMetadataArgs(args, convertToId3Tags(metadata));
    args..add('-id3v2_version')..add('3')..add(tempOutput)..add('-y');
    return _runAndReplace(args, tempOutput, mp3Path, 'MP3');
  }

  // --- FFmpeg execution + safe in-place replace ---

  /// Overridable for tests: runs an FFmpeg command, returns success.
  @visibleForTesting
  static Future<bool> Function(List<String> args) execRunner = _defaultExec;

  static Future<bool> _defaultExec(List<String> args) async {
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      return ReturnCode.isSuccess(rc);
    } catch (e) {
      debugPrint('[FfmpegMetadata] execute error: $e');
      return false;
    }
  }

  static Future<bool> _runAndReplace(
    List<String> args,
    String tempOutput,
    String originalPath,
    String label,
  ) async {
    final ok = await execRunner(args);
    final temp = File(tempOutput);
    if (ok) {
      try {
        if (await temp.exists()) {
          final original = File(originalPath);
          if (await original.exists()) await original.delete();
          await temp.copy(originalPath);
          await temp.delete();
          debugPrint('[FfmpegMetadata] $label metadata embedded');
          return true;
        }
        debugPrint('[FfmpegMetadata] temp $label output missing: $tempOutput');
      } catch (e) {
        debugPrint('[FfmpegMetadata] replace failed ($label): $e');
      }
      return false;
    }
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}
    debugPrint('[FfmpegMetadata] $label embed failed');
    return false;
  }

  static Future<String> _nextTempPath(String ext) async {
    final dir = await getTemporaryDirectory();
    _tempCounter = (_tempCounter + 1) & 0x7fffffff;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}temp_embed_${ts}_$_tempCounter$ext';
  }

  static Future<String?> _coverPictureBase64(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      return createMetadataBlockPictureBase64(bytes, _sniffMime(imagePath, bytes));
    } catch (e) {
      debugPrint('[FfmpegMetadata] picture block error: $e');
      return null;
    }
  }

  // --- Pure helpers (unit-tested) ---

  @visibleForTesting
  static String sniffMime(String path, Uint8List data) => _sniffMime(path, data);

  static String _sniffMime(String path, Uint8List data) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (data.length >= 4 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  /// Builds a FLAC METADATA_BLOCK_PICTURE (front cover, type 3), base64-encoded
  /// for use as an Opus Vorbis comment. FFmpeg cannot attach a picture stream
  /// to Opus, so the cover must be encoded this way.
  @visibleForTesting
  static String createMetadataBlockPictureBase64(
    Uint8List imageData,
    String mimeType,
  ) {
    final mimeBytes = utf8.encode(mimeType);
    const description = '';
    final descBytes = utf8.encode(description);

    final blockSize = 4 + // picture type
        4 + mimeBytes.length + // mime length + mime
        4 + descBytes.length + // desc length + desc
        4 + 4 + 4 + 4 + // width, height, depth, colors
        4 + imageData.length; // image length + image

    final out = Uint8List(blockSize);
    final view = ByteData.view(out.buffer);
    var offset = 0;

    view.setUint32(offset, 3, Endian.big); // type 3 = front cover
    offset += 4;
    view.setUint32(offset, mimeBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;
    view.setUint32(offset, descBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + descBytes.length, descBytes);
    offset += descBytes.length;
    view.setUint32(offset, 0, Endian.big); // width
    offset += 4;
    view.setUint32(offset, 0, Endian.big); // height
    offset += 4;
    view.setUint32(offset, 0, Endian.big); // depth
    offset += 4;
    view.setUint32(offset, 0, Endian.big); // colors
    offset += 4;
    view.setUint32(offset, imageData.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + imageData.length, imageData);

    return base64Encode(out);
  }

  /// Normalizes arbitrary metadata keys to canonical Vorbis comment keys.
  @visibleForTesting
  static Map<String, String> normalizeToVorbisComments(
    Map<String, String> metadata,
  ) {
    final vorbis = <String, String>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final value = entry.value;
      if (value.isEmpty) continue;
      switch (key) {
        case 'TITLE':
          vorbis['TITLE'] = value;
          break;
        case 'ARTIST':
          vorbis['ARTIST'] = value;
          break;
        case 'ALBUM':
          vorbis['ALBUM'] = value;
          break;
        case 'ALBUMARTIST':
          vorbis['ALBUMARTIST'] = value;
          break;
        case 'TRACKNUMBER':
        case 'TRACK':
          if (value != '0') vorbis['TRACKNUMBER'] = value;
          break;
        case 'DISCNUMBER':
        case 'DISC':
          if (value != '0') vorbis['DISCNUMBER'] = value;
          break;
        case 'DATE':
          vorbis['DATE'] = value;
          break;
        case 'GENRE':
          vorbis['GENRE'] = value;
          break;
        case 'ISRC':
          vorbis['ISRC'] = value;
          break;
        case 'LABEL':
        case 'ORGANIZATION':
          vorbis['ORGANIZATION'] = value;
          break;
        case 'COPYRIGHT':
          vorbis['COPYRIGHT'] = value;
          break;
        case 'COMPOSER':
          vorbis['COMPOSER'] = value;
          break;
        case 'LYRICS':
        case 'UNSYNCEDLYRICS':
          vorbis['LYRICS'] = value;
          vorbis['UNSYNCEDLYRICS'] = value;
          break;
      }
    }
    return vorbis;
  }

  /// Appends `-metadata KEY=VALUE` args from normalized Vorbis comments.
  /// Using separate list elements means values with newlines/quotes/`=` need
  /// no escaping.
  @visibleForTesting
  static void appendVorbisMetadataArgs(
    List<String> args,
    Map<String, String> metadata,
  ) {
    final vorbis = normalizeToVorbisComments(metadata);
    for (final entry in vorbis.entries) {
      args
        ..add('-metadata')
        ..add('${entry.key}=${entry.value}');
    }
  }

  @visibleForTesting
  static void appendMappedMetadataArgs(
    List<String> args,
    Map<String, String> metadata,
  ) {
    for (final entry in metadata.entries) {
      args
        ..add('-metadata')
        ..add('${entry.key}=${entry.value}');
    }
  }

  /// Maps Vorbis comment keys to M4A/MP4 tag names for FFmpeg.
  @visibleForTesting
  static Map<String, String> convertToM4aTags(Map<String, String> metadata) {
    final out = <String, String>{};
    for (final entry in normalizeToVorbisComments(metadata).entries) {
      switch (entry.key) {
        case 'TITLE':
          out['title'] = entry.value;
          break;
        case 'ARTIST':
          out['artist'] = entry.value;
          break;
        case 'ALBUM':
          out['album'] = entry.value;
          break;
        case 'ALBUMARTIST':
          out['album_artist'] = entry.value;
          break;
        case 'TRACKNUMBER':
          out['track'] = entry.value;
          break;
        case 'DISCNUMBER':
          out['disc'] = entry.value;
          break;
        case 'DATE':
          out['date'] = entry.value;
          break;
        case 'GENRE':
          out['genre'] = entry.value;
          break;
        case 'ISRC':
          out['isrc'] = entry.value;
          break;
        case 'COMPOSER':
          out['composer'] = entry.value;
          break;
        case 'COPYRIGHT':
          out['copyright'] = entry.value;
          break;
        case 'ORGANIZATION':
          out['organization'] = entry.value;
          break;
        case 'LYRICS':
          out['lyrics'] = entry.value;
          break;
      }
    }
    return out;
  }

  /// Maps Vorbis comment keys to ID3 (MP3) tag names for FFmpeg.
  @visibleForTesting
  static Map<String, String> convertToId3Tags(Map<String, String> metadata) {
    final out = <String, String>{};
    for (final entry in normalizeToVorbisComments(metadata).entries) {
      switch (entry.key) {
        case 'TITLE':
          out['title'] = entry.value;
          break;
        case 'ARTIST':
          out['artist'] = entry.value;
          break;
        case 'ALBUM':
          out['album'] = entry.value;
          break;
        case 'ALBUMARTIST':
          out['album_artist'] = entry.value;
          break;
        case 'TRACKNUMBER':
          out['track'] = entry.value;
          break;
        case 'DISCNUMBER':
          out['disc'] = entry.value;
          break;
        case 'DATE':
          out['date'] = entry.value;
          break;
        case 'GENRE':
          out['genre'] = entry.value;
          break;
        case 'ISRC':
          out['TSRC'] = entry.value;
          break;
        case 'COMPOSER':
          out['composer'] = entry.value;
          break;
        case 'LYRICS':
          out['lyrics'] = entry.value;
          break;
      }
    }
    return out;
  }
}
