import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/verified_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/spectrogram_placeholder.dart';

const _flacVerified = LibraryEntry(
  path: '/music/Artist/Album/01 Song.flac',
  name: '01 Song.flac',
  sizeBytes: 20971520, // 20 MB
  artistName: 'Artist',
  albumName: 'Album',
  format: 'FLAC',
  verified: true,
);

const _mp3Unverified = LibraryEntry(
  path: '/music/Track.mp3',
  name: 'Track.mp3',
  sizeBytes: 5242880, // 5 MB
  artistName: null,
  albumName: null,
  format: 'MP3',
  verified: false,
);

Widget buildVerifiedScreen(LibraryEntry entry) {
  return ProviderScope(
    child: MaterialApp(
      theme: appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: VerifiedScreen(entry: entry),
    ),
  );
}

void main() {
  group('VerifiedScreen — verified FLAC entry', () {
    testWidgets('shows verified badge text', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified));
      await tester.pumpAndSettle();

      expect(find.text('Genuine lossless'), findsOneWidget);
    });

    testWidgets('shows format value in stats grid', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified));
      await tester.pumpAndSettle();

      // Format stat value — the actual format string
      expect(find.text('FLAC'), findsWidgets);
    });

    testWidgets('renders SpectrogramPlaceholder widget', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified));
      await tester.pumpAndSettle();

      expect(find.byType(SpectrogramPlaceholder), findsOneWidget);
    });

    testWidgets('shows em-dash placeholders for unavailable metrics',
        (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified));
      await tester.pumpAndSettle();

      // Both bit depth and sample rate show '—'
      expect(find.text('—'), findsAtLeastNWidgets(2));
    });

    testWidgets('shows serve title', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified));
      await tester.pumpAndSettle();

      // Scroll to bottom to ensure serve row is visible
      await tester.scrollUntilVisible(
        find.text('Serve to other devices'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Serve to other devices'), findsOneWidget);
    });
  });

  group('VerifiedScreen — unverified MP3 entry', () {
    testWidgets('shows unverified badge text', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_mp3Unverified));
      await tester.pumpAndSettle();

      expect(find.text('Not verified'), findsOneWidget);
    });

    testWidgets('does NOT show verified lossless text', (tester) async {
      await tester.pumpWidget(buildVerifiedScreen(_mp3Unverified));
      await tester.pumpAndSettle();

      expect(find.text('Genuine lossless'), findsNothing);
    });
  });
}
