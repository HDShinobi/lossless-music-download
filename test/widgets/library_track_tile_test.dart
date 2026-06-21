import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';

const flacEntry = LibraryEntry(
  path: '/downloads/Artist/Album/01 Song.flac',
  name: '01 Song.flac',
  sizeBytes: 5000000,
  artistName: 'Artist',
  albumName: 'Album',
  format: 'FLAC',
  verified: true,
);

const mp3Entry = LibraryEntry(
  path: '/downloads/Artist/Album/02 Song.mp3',
  name: '02 Song.mp3',
  sizeBytes: 3000000,
  artistName: 'Artist',
  albumName: 'Album',
  format: 'MP3',
  verified: false,
);

Widget buildTile(LibraryEntry entry) {
  return MaterialApp(
    theme: appTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: LibraryTrackTile(entry: entry)),
  );
}

void main() {
  group('LibraryTrackTile', () {
    testWidgets('FLAC entry shows FLAC badge and verified check icon',
        (tester) async {
      await tester.pumpWidget(buildTile(flacEntry));
      await tester.pumpAndSettle();

      // Format badge should show 'FLAC'
      final badgeFinder = find.byKey(const Key('formatBadge'));
      expect(badgeFinder, findsOneWidget);
      expect(find.descendant(of: badgeFinder, matching: find.text('FLAC')),
          findsOneWidget);

      // Verified check icon should be present
      expect(find.byKey(const Key('verifiedCheck')), findsOneWidget);
    });

    testWidgets('MP3 entry shows MP3 badge and no verified check icon',
        (tester) async {
      await tester.pumpWidget(buildTile(mp3Entry));
      await tester.pumpAndSettle();

      // Format badge should show 'MP3'
      final badgeFinder = find.byKey(const Key('formatBadge'));
      expect(badgeFinder, findsOneWidget);
      expect(find.descendant(of: badgeFinder, matching: find.text('MP3')),
          findsOneWidget);

      // Verified check icon should NOT be present
      expect(find.byKey(const Key('verifiedCheck')), findsNothing);
    });
  });
}
