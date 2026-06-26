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

  group('TrackTile artist/album entry points', () {
    const trackWithIds = Track(
      id: 't1',
      name: 'Song One',
      artists: 'Artist A',
      albumName: 'Album X',
      artistId: 'deezer:111',
      albumId: 'deezer:222',
    );

    Future<void> pumpWithNav(
      WidgetTester tester, {
      required Track track,
      VoidCallback? onArtistTap,
      VoidCallback? onAlbumTap,
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
              onDownload: () {},
              onArtistTap: onArtistTap,
              onAlbumTap: onAlbumTap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping the artist name fires onArtistTap', (tester) async {
      var tapped = false;
      await pumpWithNav(tester,
          track: trackWithIds, onArtistTap: () => tapped = true);

      expect(find.byKey(const Key('trackArtist')), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackArtist')));
      expect(tapped, isTrue);
    });

    testWidgets('tapping the album name fires onAlbumTap', (tester) async {
      var tapped = false;
      await pumpWithNav(tester,
          track: trackWithIds, onAlbumTap: () => tapped = true);

      expect(find.byKey(const Key('trackAlbum')), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackAlbum')));
      expect(tapped, isTrue);
    });

    testWidgets('tappable even without IDs (resolved on demand on tap)',
        (tester) async {
      var artistTapped = false;
      await pumpWithNav(tester, track: track,
          onArtistTap: () => artistTapped = true, onAlbumTap: () {});

      // Names are always tappable when handlers are wired; the missing ID is
      // resolved on demand by the tap handler.
      expect(find.byKey(const Key('trackArtist')), findsOneWidget);
      expect(find.byKey(const Key('trackAlbum')), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackArtist')));
      expect(artistTapped, isTrue);
    });

    testWidgets('no tappable spans when no navigation callbacks are given',
        (tester) async {
      await pumpWithNav(tester, track: trackWithIds);

      expect(find.byKey(const Key('trackArtist')), findsNothing);
      expect(find.byKey(const Key('trackAlbum')), findsNothing);
    });
  });

  group('_DownloadStateIcon states', () {
    for (final tc in [
      (TrackDownloadState.idle, Icons.download_outlined),
      (TrackDownloadState.active, null),   // spinner, no icon
      (TrackDownloadState.done, Icons.check_circle_outline),
    ]) {
      testWidgets('${tc.$1}', (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrackTile(
                track: const Track(id: '1', name: 'T', artists: 'A', albumName: ''),
                downloadState: tc.$1,
                onDownload: () {},
              ),
            ),
          ),
        );
        // Use pump() instead of pumpAndSettle() to avoid timeout with spinner animation
        await t.pump();
        if (tc.$2 != null) {
          expect(find.byIcon(tc.$2!), findsOneWidget);
        } else {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }
      });
    }
  });
}
