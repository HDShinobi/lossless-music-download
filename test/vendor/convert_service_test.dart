import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/vendor/spotiflac/convert_service.dart';

void main() {
  group('convertOutputExtension', () {
    test('maps each format to its container extension', () {
      expect(convertOutputExtension('mp3'), '.mp3');
      expect(convertOutputExtension('opus'), '.opus');
      expect(convertOutputExtension('aac'), '.m4a');
      expect(convertOutputExtension('flac'), '.flac');
      expect(convertOutputExtension('wav'), '.wav');
    });

    test('is case-insensitive and returns null for unsupported', () {
      expect(convertOutputExtension('MP3'), '.mp3');
      expect(convertOutputExtension('ogg'), isNull);
    });
  });

  group('convertOutputPath', () {
    test('swaps the extension on the input path', () {
      expect(
        convertOutputPath('/music/Song.flac', 'mp3'),
        '/music/Song.mp3',
      );
      expect(
        convertOutputPath('/a/b/Track Name.flac', 'aac'),
        '/a/b/Track Name.m4a',
      );
    });
  });

  group('buildConvertArgs', () {
    test('lossy targets carry the bitrate flag', () {
      final mp3 = buildConvertArgs(
          input: '/in.flac', output: '/out.mp3', format: 'mp3', bitrate: '320k');
      expect(mp3, contains('libmp3lame'));
      expect(mp3, containsAllInOrder(['-b:a', '320k']));
      expect(mp3, containsAllInOrder(['-i', '/in.flac']));
      expect(mp3, containsAllInOrder(['/out.mp3', '-y']));

      final opus = buildConvertArgs(
          input: '/in.flac', output: '/out.opus', format: 'opus', bitrate: '256k');
      expect(opus, contains('libopus'));
      expect(opus, containsAllInOrder(['-b:a', '256k']));

      final aac = buildConvertArgs(
          input: '/in.flac', output: '/out.m4a', format: 'aac', bitrate: '256k');
      expect(aac, contains('aac'));
      expect(aac, containsAllInOrder(['-b:a', '256k']));
    });

    test('lossless targets (flac/wav) omit the bitrate flag', () {
      final flac = buildConvertArgs(
          input: '/in.wav', output: '/out.flac', format: 'flac', bitrate: '320k');
      expect(flac, contains('flac'));
      expect(flac, isNot(contains('-b:a')));

      final wav = buildConvertArgs(
          input: '/in.flac', output: '/out.wav', format: 'wav', bitrate: '320k');
      expect(wav, contains('pcm_s16le'));
      expect(wav, isNot(contains('-b:a')));
    });

    test('always overwrites output (-y) and maps only audio', () {
      final args = buildConvertArgs(
          input: '/in.flac', output: '/out.mp3', format: 'mp3', bitrate: '320k');
      expect(args, contains('-y'));
      expect(args, containsAllInOrder(['-map', '0:a']));
      expect(args, containsAllInOrder(['-map_metadata', '0']));
    });
  });
}
