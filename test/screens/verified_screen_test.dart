import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/verified_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/vendor/spotiflac/audio_analysis_widget.dart';

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
  // The real audio analysis (FFmpeg decode + FFT) cannot run in a widget test,
  // so we pump a single frame (NOT pumpAndSettle, which would wait forever on
  // the unavailable native plugin) and assert the screen scaffolding renders:
  // our brand verdict badge + the vendored AudioAnalysisCard.

  testWidgets('verified FLAC: shows Genuine lossless badge + analysis card',
      (tester) async {
    await tester.pumpWidget(_screen(_flacVerified));
    await tester.pump();

    expect(find.text('Genuine lossless'), findsOneWidget);
    expect(find.byType(AudioAnalysisCard), findsOneWidget);
  });

  testWidgets('unverified MP3: shows Not verified, not Genuine lossless',
      (tester) async {
    await tester.pumpWidget(_screen(_mp3Unverified));
    await tester.pump();

    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Genuine lossless'), findsNothing);
    expect(find.byType(AudioAnalysisCard), findsOneWidget);
  });
}
