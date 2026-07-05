import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/util/lyrics_parser.dart';

void main() {
  group('LyricsParser.parse', () {
    test('empty input → ParsedLyrics.empty', () {
      expect(LyricsParser.parse('').isEmpty, isTrue);
      expect(LyricsParser.parse(null).isEmpty, isTrue);
    });

    test('plain text (no timestamps) → synced=false, plainText set', () {
      final r = LyricsParser.parse('hello\nworld');
      expect(r.synced, isFalse);
      expect(r.plainText, 'hello\nworld');
      expect(r.lines, isEmpty);
    });

    test('LRC line timestamps → synced lines in order', () {
      final r = LyricsParser.parse('[00:12.50]line B\n[00:01.00]line A');
      expect(r.synced, isTrue);
      expect(r.lines.map((l) => l.text).toList(), ['line A', 'line B']);
      expect(r.lines.first.time, const Duration(seconds: 1));
    });

    test('repeated timestamps on one line → multiple lines (chorus)', () {
      final r = LyricsParser.parse('[00:01.00][00:10.00]chorus');
      expect(r.lines.length, 2);
      expect(r.lines.every((l) => l.text == 'chorus'), isTrue);
    });

    test('enhanced-LRC word timings parsed', () {
      final r = LyricsParser.parse('[00:01.00]<00:01.00>Hel <00:01.50>lo');
      expect(r.wordSynced, isTrue);
      expect(r.lines.single.words.length, 2);
      expect(r.lines.single.text, 'Hel lo');
    });

    test('[offset:] shifts timing earlier', () {
      final r = LyricsParser.parse('[offset:500]\n[00:02.00]x');
      expect(r.lines.single.time, const Duration(milliseconds: 1500));
    });

    test('TTML parsed to synced lines', () {
      const ttml =
          '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
          '<p begin="00:01.000" end="00:02.000">hi</p></div></body></tt>';
      final r = LyricsParser.parse(ttml);
      expect(r.synced, isTrue);
      expect(r.lines.single.text, 'hi');
      expect(r.lines.single.time, const Duration(seconds: 1));
    });
  });
}
