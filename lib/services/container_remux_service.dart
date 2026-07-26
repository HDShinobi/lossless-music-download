import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';

/// Finalizes MP4-delivered downloads on the Dart fallback path: decrypts them
/// when the source supplied a key, and unwraps a FLAC stream out of the MP4 box.
///
/// Amazon's lossless tier streams an **encrypted** MP4 and returns the key in the
/// download result (`decryption: {strategy: "ffmpeg.mov_key", key, input_format:
/// "mov", output_extension: ".flac"}`). go_backend only forwards that; applying
/// it is the app's job. Skipping it leaves a file whose container labels read as
/// FLAC 24-bit — so the library shows hi-res and tagging appears to work — while
/// every audio frame is ciphertext that no player can decode.
///
/// `-decryption_key` is only honoured by the MOV/MP4 demuxer, hence `-f mov`.
/// After decryption a plain `-c copy` is correct: the payload is already FLAC.
///
/// The native worker path has its own copy of this in Mp4FlacUnwrapper.kt; the
/// two must stay in step.
class ContainerRemuxService {
  /// Injectable seam so tests do not need a real ffmpeg.
  static Future<bool> Function(List<String> args) execRunner = defaultExec;

  static Future<bool> defaultExec(List<String> args) async {
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      return ReturnCode.isSuccess(await session.getReturnCode());
    } catch (e) {
      debugPrint('[ContainerRemux] execute error: $e');
      return false;
    }
  }

  /// Strategy aliases that mean "pass the key to ffmpeg's MOV demuxer".
  static const _movKeyStrategies = {
    '',
    'ffmpeg.mov_key',
    'ffmpeg_mov_key',
    'mov_decryption_key',
    'mp4_decryption_key',
    'ffmpeg.mp4_decryption_key',
  };

  /// Whether [path] is a plain local MP4-family file worth attempting.
  static bool looksLikeMp4Container(String path) {
    if (path.startsWith('content://') || path.startsWith('/proc/self/fd/')) {
      return false;
    }
    final lower = path.toLowerCase();
    return lower.endsWith('.m4a') || lower.endsWith('.mp4');
  }

  /// Returns the finished audio path, or null when nothing changed — a normal
  /// AAC/ALAC download is a good file that simply needs no work, and a
  /// half-processed one would be worse than none.
  static Future<String?> finalizeDownload(Map<String, dynamic> result) async {
    final path = result['file_path']?.toString() ?? '';
    if (!looksLikeMp4Container(path)) return null;
    if (!await File(path).exists()) return null;

    final decryption = result['decryption'];
    final info = decryption is Map ? decryption.cast<String, dynamic>() : null;
    final key = (info?['key'] ?? result['decryption_key'] ?? '')
        .toString()
        .trim();
    if (key.isEmpty) return null;

    final strategy = (info?['strategy'] ?? '').toString().trim().toLowerCase();
    if (!_movKeyStrategies.contains(strategy)) {
      debugPrint('[ContainerRemux] unsupported strategy "$strategy", keeping $path');
      return null;
    }

    // The extension picks the container the decrypted stream can legally live in
    // (.flac for FLAC; .mp4 for eac3/ac4/opus, which the flac muxer rejects).
    var ext = (info?['output_extension'] ?? result['output_extension'] ?? '')
        .toString()
        .trim();
    if (ext.isEmpty) ext = '.flac';
    if (!ext.startsWith('.')) ext = '.$ext';

    final out = '${path.substring(0, path.lastIndexOf('.'))}$ext';
    if (out == path) return null;
    final outFile = File(out);
    if (await outFile.exists()) await outFile.delete();

    final demuxer =
        (info?['input_format'] ?? '').toString().trim().isEmpty
            ? 'mov'
            : (info!['input_format'] as String).trim();

    final ok = await execRunner([
      '-y',
      '-decryption_key',
      key,
      '-f',
      demuxer,
      '-i',
      path,
      '-map',
      '0:a:0',
      '-c',
      'copy',
      out,
    ]);

    if (!ok || !await outFile.exists() || await outFile.length() == 0) {
      if (await outFile.exists()) await outFile.delete();
      debugPrint('[ContainerRemux] decryption failed, keeping $path');
      return null;
    }

    try {
      await File(path).delete();
    } catch (e) {
      // Leaving both would show the track twice in the library.
      debugPrint('[ContainerRemux] could not remove encrypted $path: $e');
    }
    return out;
  }
}
