// Adapted from SpotiFLAC-Mobile (MIT): convertAudioFormat() in
// lib/services/ffmpeg_service.dart. See SYNC.md. The FFmpeg codec commands are
// ported faithfully (libmp3lame / libopus / aac / flac / pcm); the file I/O and
// re-tagging are adapted to our ffmpeg_kit_full + FfmpegMetadataService.
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';

/// Target formats the converter supports.
const convertFormats = ['flac', 'mp3', 'opus', 'aac', 'wav'];

/// Bitrate choices offered for lossy targets.
const convertBitrates = ['320k', '256k', '192k', '128k'];

const _extensions = {
  'mp3': '.mp3',
  'opus': '.opus',
  'aac': '.m4a',
  'flac': '.flac',
  'wav': '.wav',
};

const _lossless = {'flac', 'wav'};

/// Container extension for [format], or null if unsupported. Case-insensitive.
String? convertOutputExtension(String format) => _extensions[format.toLowerCase()];

/// The output path for converting [inputPath] to [format] (extension swapped).
String convertOutputPath(String inputPath, String format) {
  final ext = convertOutputExtension(format)!;
  final dot = inputPath.lastIndexOf('.');
  final base = dot >= 0 ? inputPath.substring(0, dot) : inputPath;
  return '$base$ext';
}

/// Builds the FFmpeg argument list to convert [input] → [output] as [format].
/// Pure and unit-tested. Lossy targets include `-b:a [bitrate]`; lossless
/// (flac/wav) omit it. Ported from SpotiFLAC's per-format commands.
List<String> buildConvertArgs({
  required String input,
  required String output,
  required String format,
  required String bitrate,
}) {
  final f = format.toLowerCase();
  final codec = switch (f) {
    'mp3' => ['-codec:a', 'libmp3lame', '-b:a', bitrate, '-id3v2_version', '3'],
    'opus' => [
        '-codec:a',
        'libopus',
        '-b:a',
        bitrate,
        '-vbr',
        'on',
        '-compression_level',
        '10',
      ],
    'aac' => ['-codec:a', 'aac', '-b:a', bitrate, '-f', 'mp4'],
    'flac' => ['-codec:a', 'flac', '-compression_level', '8'],
    'wav' => ['-codec:a', 'pcm_s16le'],
    _ => <String>[],
  };
  return [
    '-v', 'error', '-hide_banner',
    '-i', input,
    ...codec,
    '-map', '0:a',
    '-map_metadata', '0', // carry text tags over to the converted file
    output,
    '-y',
  ];
}

/// Whether [format] is a lossless target (no bitrate selection needed).
bool isLosslessConvertTarget(String format) =>
    _lossless.contains(format.toLowerCase());

/// Converts [inputPath] to [format]/[bitrate] via FFmpeg. Returns the new file
/// path on success (the original is left in place for the caller to delete), or
/// null on failure / unsupported format.
class ConvertService {
  ConvertService._();

  /// Overridable in tests; defaults to running FFmpeg with the given args and
  /// reporting success.
  static Future<bool> Function(List<String> args) runner = _defaultRun;

  static Future<bool> _defaultRun(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    return ReturnCode.isSuccess(rc);
  }

  static Future<String?> convert({
    required String inputPath,
    required String format,
    required String bitrate,
  }) async {
    if (convertOutputExtension(format) == null) return null;
    final output = convertOutputPath(inputPath, format);
    if (output == inputPath) return null; // same format

    final ok = await runner(buildConvertArgs(
      input: inputPath,
      output: output,
      format: format,
      bitrate: bitrate,
    ));
    if (!ok) {
      // Clean up a partial output on failure.
      try {
        final f = File(output);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return null;
    }
    return output;
  }
}
