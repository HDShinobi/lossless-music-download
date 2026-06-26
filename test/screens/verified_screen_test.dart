import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/verified_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

const _flacVerified = LibraryEntry(
  path: '/music/Artist/Album/01 Song.flac',
  name: '01 Song.flac',
  sizeBytes: 20971520,
  artistName: 'Artist',
  albumName: 'Album',
  format: 'FLAC',
  verified: true,
);

const _mp3Unverified = LibraryEntry(
  path: '/music/Track.mp3',
  name: 'Track.mp3',
  sizeBytes: 5242880,
  artistName: null,
  albumName: null,
  format: 'MP3',
  verified: false,
);

Widget _screen(LibraryEntry entry) => ProviderScope(
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: VerifiedScreen(entry: entry),
      ),
    );

void main() {
  testWidgets('verified FLAC: shows Genuine lossless badge', (tester) async {
    await tester.pumpWidget(_screen(_flacVerified));
    await tester.pump();

    expect(find.text('Genuine lossless'), findsOneWidget);
  });

  testWidgets('unverified MP3: shows Not verified, not Genuine lossless',
      (tester) async {
    await tester.pumpWidget(_screen(_mp3Unverified));
    await tester.pump();

    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Genuine lossless'), findsNothing);
  });
}
