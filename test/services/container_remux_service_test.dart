import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/container_remux_service.dart';

Future<String> _tempFile(String name, {String body = 'audio'}) async {
  final dir = await Directory.systemTemp.createTemp('remux_test');
  final f = File('${dir.path}/$name');
  await f.writeAsString(body);
  return f.path;
}

/// The shape the Amazon extension returns for its lossless tier.
Map<String, dynamic> _encryptedResult(
  String path, {
  String key = 'deadbeef',
  String strategy = 'ffmpeg.mov_key',
  String outputExtension = '.flac',
}) => {
      'file_path': path,
      'decryption': {
        'strategy': strategy,
        'key': key,
        'input_format': 'mov',
        'output_extension': outputExtension,
      },
    };

void main() {
  setUp(() => ContainerRemuxService.execRunner = ContainerRemuxService.defaultExec);
  tearDown(
      () => ContainerRemuxService.execRunner = ContainerRemuxService.defaultExec);

  group('looksLikeMp4Container', () {
    test('accepts the extensions Amazon lossless arrives as', () {
      expect(ContainerRemuxService.looksLikeMp4Container('/a/b.m4a'), isTrue);
      expect(ContainerRemuxService.looksLikeMp4Container('/a/b.MP4'), isTrue);
    });

    test('rejects everything else, including files already FLAC', () {
      for (final p in ['/a/b.flac', '/a/b.opus', '/a/b.mp3', '/a/b']) {
        expect(ContainerRemuxService.looksLikeMp4Container(p), isFalse,
            reason: p);
      }
    });

    test('rejects paths the app cannot open as plain files', () {
      expect(
        ContainerRemuxService.looksLikeMp4Container('content://media/1.m4a'),
        isFalse,
      );
      expect(
        ContainerRemuxService.looksLikeMp4Container('/proc/self/fd/7'),
        isFalse,
      );
    });
  });

  group('finalizeDownload', () {
    test('decrypts into a .flac beside the original and removes it', () async {
      final path = await _tempFile('track.m4a');
      List<String>? args;
      ContainerRemuxService.execRunner = (a) async {
        args = a;
        await File(a.last).writeAsString('flac bytes');
        return true;
      };

      final out =
          await ContainerRemuxService.finalizeDownload(_encryptedResult(path));

      expect(out, path.replaceAll('.m4a', '.flac'));
      // The key must reach ffmpeg, and via the MOV demuxer — -decryption_key is
      // only honoured there.
      expect(args, containsAllInOrder(['-decryption_key', 'deadbeef']));
      expect(args, containsAllInOrder(['-f', 'mov']));
      // Stream copy, never a re-encode: after decryption the payload is already
      // FLAC, and a transcode would burn CPU for nothing.
      expect(args, contains('copy'));
      expect(File(path).existsSync(), isFalse);
      expect(File(out!).existsSync(), isTrue);
    });

    test('honours the container the extension asked for', () async {
      // eac3/ac4/opus cannot live in a .flac container, so the extension asks
      // for .mp4 instead.
      final path = await _tempFile('track.m4a');
      ContainerRemuxService.execRunner = (a) async {
        await File(a.last).writeAsString('bytes');
        return true;
      };

      final out = await ContainerRemuxService.finalizeDownload(
        _encryptedResult(path, outputExtension: '.mp4'),
      );

      expect(out, endsWith('.mp4'));
    });

    test('does nothing when there is no key — an ordinary AAC download',
        () async {
      final path = await _tempFile('track.m4a');
      var called = false;
      ContainerRemuxService.execRunner = (_) async {
        called = true;
        return true;
      };

      expect(
        await ContainerRemuxService.finalizeDownload({'file_path': path}),
        isNull,
      );
      expect(called, isFalse, reason: 'must not shell out with nothing to do');
      expect(File(path).existsSync(), isTrue);
    });

    test('refuses a decryption strategy it does not implement', () async {
      final path = await _tempFile('track.m4a');
      var called = false;
      ContainerRemuxService.execRunner = (_) async {
        called = true;
        return true;
      };

      final out = await ContainerRemuxService.finalizeDownload(
        _encryptedResult(path, strategy: 'widevine.cdm'),
      );

      expect(out, isNull);
      expect(called, isFalse,
          reason: 'guessing at an unknown scheme would corrupt the file');
      expect(File(path).existsSync(), isTrue);
    });

    test('leaves the encrypted file intact when ffmpeg fails', () async {
      final path = await _tempFile('track.m4a');
      ContainerRemuxService.execRunner = (a) async {
        await File(a.last).writeAsString('');
        return false;
      };

      expect(
        await ContainerRemuxService.finalizeDownload(_encryptedResult(path)),
        isNull,
      );
      expect(File(path).existsSync(), isTrue,
          reason: 'never destroy the only copy we have');
      expect(File(path.replaceAll('.m4a', '.flac')).existsSync(), isFalse,
          reason: 'no partial output may be left for the library to scan');
    });

    test('treats an empty output as failure even if ffmpeg claims success',
        () async {
      final path = await _tempFile('track.m4a');
      ContainerRemuxService.execRunner = (a) async {
        await File(a.last).writeAsString('');
        return true;
      };

      expect(
        await ContainerRemuxService.finalizeDownload(_encryptedResult(path)),
        isNull,
      );
      expect(File(path).existsSync(), isTrue);
    });

    test('does nothing for a non-MP4 download', () async {
      final path = await _tempFile('track.opus');
      var called = false;
      ContainerRemuxService.execRunner = (_) async {
        called = true;
        return true;
      };

      expect(
        await ContainerRemuxService.finalizeDownload(_encryptedResult(path)),
        isNull,
      );
      expect(called, isFalse);
    });

    test('returns null when the source file is missing', () async {
      expect(
        await ContainerRemuxService.finalizeDownload(
          _encryptedResult('/nope/missing.m4a'),
        ),
        isNull,
      );
    });
  });
}
