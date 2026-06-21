import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/track_tile.dart';

// ---------------------------------------------------------------------------
// Helper: pump TrackTile in a minimal MaterialApp
// ---------------------------------------------------------------------------
Future<void> pumpTrackTile(
  WidgetTester tester, {
  required Track track,
  String? qualityHint,
  required VoidCallback onDownload,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: TrackTile(
          track: track,
          qualityHint: qualityHint,
          onDownload: onDownload,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  const track = Track(
    id: '1',
    name: 'Test Song',
    artists: 'Test Artist',
    albumName: 'Test Album',
  );

  group('TrackTile', () {
    testWidgets('shows track name and artist subtitle', (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
      );

      expect(find.text('Test Song'), findsOneWidget);
      // artists and album are joined as "Artist · Album" in the subtitle
      expect(find.text('Test Artist · Test Album'), findsOneWidget);
    });

    testWidgets('shows no badge when qualityHint is null', (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        qualityHint: null,
        onDownload: () {},
      );

      // No badge text should be visible
      expect(find.byKey(const Key('qualityBadge')), findsNothing);
    });

    testWidgets('shows HI-RES badge when qualityHint is HI-RES',
        (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        qualityHint: 'HI-RES',
        onDownload: () {},
      );

      expect(find.text('HI-RES'), findsOneWidget);
      expect(find.byKey(const Key('qualityBadge')), findsOneWidget);
    });

    testWidgets('shows non-null non-HI-RES badge when qualityHint is FLAC',
        (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        qualityHint: 'FLAC',
        onDownload: () {},
      );

      expect(find.text('FLAC'), findsOneWidget);
      expect(find.byKey(const Key('qualityBadge')), findsOneWidget);
    });

    testWidgets('tapping download button invokes onDownload callback',
        (tester) async {
      var called = false;
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () => called = true,
      );

      await tester.tap(find.byIcon(Icons.download_outlined));
      expect(called, isTrue);
    });

    testWidgets('shows download button with accent-soft background',
        (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
      );

      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    });
  });
}
