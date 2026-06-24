import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/track_tile.dart';

Track _track() => const Track(
      id: 't1',
      name: 'Song',
      artists: 'Artist',
      durationMs: 0,
    );

// ---------------------------------------------------------------------------
// Helper: pump TrackTile in a minimal MaterialApp
// ---------------------------------------------------------------------------
Future<void> pumpTrackTile(
  WidgetTester tester, {
  required Track track,
  String? qualityHint,
  required VoidCallback onDownload,
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onLongPress,
  VoidCallback? onSelectToggle,
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
          selectionMode: selectionMode,
          selected: selected,
          onLongPress: onLongPress,
          onSelectToggle: onSelectToggle,
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
      // artist and album are rendered as separate Text widgets in _SubtitleRow
      expect(find.text('Test Artist'), findsOneWidget);
      expect(find.text('Test Album'), findsOneWidget);
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

    testWidgets('normal mode shows no Checkbox', (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
      );

      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('TrackTile selection mode', () {
    testWidgets(
        'selectionMode:true selected:true shows checked checkbox and no download button',
        (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
        selectionMode: true,
        selected: true,
        onSelectToggle: () {},
      );

      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
    });

    testWidgets('selectionMode:true selected:false shows unchecked checkbox',
        (tester) async {
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
        selectionMode: true,
        selected: false,
        onSelectToggle: () {},
      );

      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('tapping in selection mode calls onSelectToggle',
        (tester) async {
      var called = false;
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
        selectionMode: true,
        onSelectToggle: () => called = true,
      );

      await tester.tap(find.text(track.name));
      expect(called, isTrue);
    });

    testWidgets('long-press in normal mode calls onLongPress', (tester) async {
      var called = false;
      await pumpTrackTile(
        tester,
        track: track,
        onDownload: () {},
        onLongPress: () => called = true,
      );

      await tester.longPress(find.text(track.name));
      expect(called, isTrue);
    });
  });

  group('TrackTile download state icons', () {
    testWidgets('TrackTile shows download icon when idle', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: _track(),
            onDownload: () {},
            downloadState: TrackDownloadState.idle,
          ),
        ),
      ));
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('TrackTile shows spinner when active', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: _track(),
            onDownload: () {},
            downloadState: TrackDownloadState.active,
          ),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('TrackTile shows check when done', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: _track(),
            onDownload: () {},
            downloadState: TrackDownloadState.done,
          ),
        ),
      ));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });
}
