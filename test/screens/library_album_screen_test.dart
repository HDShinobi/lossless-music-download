import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_album_screen.dart';

LibraryEntry _entry(
  String title, {
  String artist = 'Ed Sheeran',
  String album = '÷ (Deluxe)',
  int? trackNumber,
  int? discNumber,
}) {
  return LibraryEntry(
    path: '/x/$title.flac',
    name: '$title.flac',
    title: title,
    sizeBytes: 0,
    artistName: artist,
    albumName: album,
    format: 'FLAC',
    verified: true,
    trackNumber: trackNumber,
    discNumber: discNumber,
  );
}

Widget _buildScreen(List<LibraryEntry> entries) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith((_) async => entries),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: LibraryAlbumScreen(artistName: 'Ed Sheeran', albumName: '÷ (Deluxe)'),
    ),
  );
}

void main() {
  group('albumTracksFor', () {
    test('filters by artist+album (case-insensitive) and sorts by '
        'disc, then track number, then title', () {
      final entries = [
        _entry('Perfect', trackNumber: 4, discNumber: 1),
        _entry('Castle on the Hill', trackNumber: 2, discNumber: 1),
        _entry('Bonus', trackNumber: 1, discNumber: 2),
        _entry('Other Album Song', album: 'No.6'),
        _entry('Other Artist Song', artist: 'Adele'),
        _entry('eraser', trackNumber: 1, discNumber: 1),
      ];

      final tracks = albumTracksFor(entries, 'ed sheeran', '÷ (deluxe)');

      expect(tracks.map((e) => e.title).toList(),
          ['eraser', 'Castle on the Hill', 'Perfect', 'Bonus']);
    });

    test('tracks without numbers sort after numbered ones, by title', () {
      final entries = [
        _entry('Zulu'),
        _entry('Alpha'),
        _entry('Numbered', trackNumber: 7),
      ];
      final tracks = albumTracksFor(entries, 'Ed Sheeran', '÷ (Deluxe)');
      expect(tracks.map((e) => e.title).toList(),
          ['Numbered', 'Alpha', 'Zulu']);
    });
  });

  group('groupTracksByDisc', () {
    test('groups by disc number, null treated as disc 1', () {
      final tracks = [
        _entry('A', trackNumber: 1),
        _entry('B', trackNumber: 2, discNumber: 1),
        _entry('C', trackNumber: 1, discNumber: 2),
      ];
      final groups = groupTracksByDisc(tracks);
      expect(groups.keys.toList(), [1, 2]);
      expect(groups[1]!.map((e) => e.title).toList(), ['A', 'B']);
      expect(groups[2]!.map((e) => e.title).toList(), ['C']);
    });
  });

  group('LibraryAlbumScreen', () {
    testWidgets('shows album header and tracks in album order',
        (tester) async {
      await tester.pumpWidget(_buildScreen([
        _entry('Perfect', trackNumber: 4),
        _entry('Eraser', trackNumber: 1),
        _entry('Elsewhere', album: 'No.6'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('÷ (Deluxe)'), findsOneWidget);
      expect(find.text('Ed Sheeran'), findsOneWidget);
      expect(find.textContaining('2 tracks'), findsOneWidget);
      expect(find.text('Elsewhere'), findsNothing);

      final eraserY = tester.getTopLeft(find.text('Eraser')).dy;
      final perfectY = tester.getTopLeft(find.text('Perfect')).dy;
      expect(eraserY, lessThan(perfectY));
    });

    testWidgets('single disc shows no disc separator', (tester) async {
      await tester.pumpWidget(_buildScreen([
        _entry('Eraser', trackNumber: 1, discNumber: 1),
        _entry('Perfect', trackNumber: 4, discNumber: 1),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Disc'), findsNothing);
    });

    testWidgets('multiple discs show disc separators', (tester) async {
      await tester.pumpWidget(_buildScreen([
        _entry('Eraser', trackNumber: 1, discNumber: 1),
        _entry('Bonus', trackNumber: 1, discNumber: 2),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Disc 1'), findsOneWidget);
      expect(find.text('Disc 2'), findsOneWidget);
    });
  });
}
