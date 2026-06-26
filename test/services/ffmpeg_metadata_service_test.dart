import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/ffmpeg_metadata_service.dart';

void main() {
  group('normalizeToVorbisComments', () {
    test('maps and keeps canonical keys, drops empties', () {
      final v = FfmpegMetadataService.normalizeToVorbisComments({
        'TITLE': 'Opalite',
        'ARTIST': 'Taylor Swift',
        'LABEL': 'Republic',
        'ALBUM': '',
        'TRACKNUMBER': '0',
        'UNSYNCEDLYRICS': '[00:01.00]hi',
      });
      expect(v['TITLE'], 'Opalite');
      expect(v['ARTIST'], 'Taylor Swift');
      expect(v['ORGANIZATION'], 'Republic'); // LABEL -> ORGANIZATION
      expect(v.containsKey('ALBUM'), isFalse); // empty dropped
      expect(v.containsKey('TRACKNUMBER'), isFalse); // "0" dropped
      expect(v['LYRICS'], '[00:01.00]hi'); // UNSYNCEDLYRICS mirrors LYRICS
      expect(v['UNSYNCEDLYRICS'], '[00:01.00]hi');
    });
  });

  group('convertToM4aTags / convertToId3Tags', () {
    test('m4a uses lowercase tag names', () {
      final m = FfmpegMetadataService.convertToM4aTags({
        'TITLE': 'T',
        'ALBUMARTIST': 'A',
        'ISRC': 'US123',
      });
      expect(m['title'], 'T');
      expect(m['album_artist'], 'A');
      expect(m['isrc'], 'US123');
    });

    test('id3 maps ISRC to TSRC', () {
      final m = FfmpegMetadataService.convertToId3Tags({'ISRC': 'US123'});
      expect(m['TSRC'], 'US123');
    });
  });

  group('appendVorbisMetadataArgs', () {
    test('emits -metadata KEY=VALUE pairs verbatim (no escaping needed)', () {
      final args = <String>[];
      FfmpegMetadataService.appendVorbisMetadataArgs(args, {
        'TITLE': 'Hello = World',
        'LYRICS': 'line1\nline2',
      });
      // each flag + value is a separate list element
      final i = args.indexOf('TITLE=Hello = World');
      expect(i, greaterThan(0));
      expect(args[i - 1], '-metadata');
      final j = args.indexOf('LYRICS=line1\nline2');
      expect(j, greaterThan(0));
      expect(args[j - 1], '-metadata');
    });
  });

  group('createMetadataBlockPictureBase64', () {
    test('encodes a FLAC picture block: type=3, mime, image at tail', () {
      final img = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final b64 = FfmpegMetadataService.createMetadataBlockPictureBase64(
        img,
        'image/jpeg',
      );
      final block = base64Decode(b64);
      final view = ByteData.view(block.buffer);

      // picture type 3 (front cover)
      expect(view.getUint32(0, Endian.big), 3);
      // mime length + mime
      final mime = utf8.encode('image/jpeg');
      expect(view.getUint32(4, Endian.big), mime.length);
      final mimeStart = 8;
      expect(
        block.sublist(mimeStart, mimeStart + mime.length),
        equals(mime),
      );
      // image bytes are the final imageData.length bytes
      expect(block.sublist(block.length - img.length), equals(img));
      // image length field precedes the image data
      expect(
        view.getUint32(block.length - img.length - 4, Endian.big),
        img.length,
      );
    });
  });

  group('isNonFlacEmbeddable', () {
    test('true for lossy formats, false for flac', () {
      expect(FfmpegMetadataService.isNonFlacEmbeddable('/x/a.opus'), isTrue);
      expect(FfmpegMetadataService.isNonFlacEmbeddable('/x/a.m4a'), isTrue);
      expect(FfmpegMetadataService.isNonFlacEmbeddable('/x/a.mp3'), isTrue);
      expect(FfmpegMetadataService.isNonFlacEmbeddable('/x/a.flac'), isFalse);
    });
  });
}
