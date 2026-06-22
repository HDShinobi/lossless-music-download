import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/audio_quality.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';

// ---------------------------------------------------------------------------
// Fake bridge — returns a fixed AudioQuality for any path.
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  final AudioQuality? _quality;

  _FakeBridge(this._quality);

  @override
  Future<AudioQuality?> getAudioQuality(String path) async => _quality;
}

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

Widget buildTile(LibraryEntry entry, {BackendBridge? bridge}) {
  return ProviderScope(
    overrides: [
      if (bridge != null) backendBridgeProvider.overrideWithValue(bridge),
    ],
    child: MaterialApp(
      theme: appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: LibraryTrackTile(entry: entry)),
    ),
  );
}

void main() {
  group('LibraryTrackTile', () {
    testWidgets('FLAC entry shows FLAC badge and verified check icon',
        (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildTile(flacEntry, bridge: bridge));
      await tester.pumpAndSettle();

      // Format badge should show 'FLAC'
      final badgeFinder = find.byKey(const Key('formatBadge'));
      expect(badgeFinder, findsOneWidget);
      expect(find.descendant(of: badgeFinder, matching: find.text('FLAC')),
          findsOneWidget);

      // Verified check icon should be present
      expect(find.byKey(const Key('verifiedCheck')), findsOneWidget);
    });

    testWidgets('FLAC entry with 24-bit/96 kHz shows quality badge "24/96"',
        (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildTile(flacEntry, bridge: bridge));
      await tester.pumpAndSettle();

      // Quality badge should appear with the formatted label
      final qualityBadge = find.byKey(const Key('qualityBadge'));
      expect(qualityBadge, findsOneWidget);
      expect(
        find.descendant(of: qualityBadge, matching: find.text('24/96')),
        findsOneWidget,
      );
    });

    testWidgets('MP3 entry shows MP3 badge and no verified check icon',
        (tester) async {
      // MP3 has bitDepth=0, so quality badge shows kHz only (e.g. "44.1k")
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 0, sampleRate: 44100, bitrate: 320),
      );
      await tester.pumpWidget(buildTile(mp3Entry, bridge: bridge));
      await tester.pumpAndSettle();

      // Format badge should show 'MP3'
      final badgeFinder = find.byKey(const Key('formatBadge'));
      expect(badgeFinder, findsOneWidget);
      expect(find.descendant(of: badgeFinder, matching: find.text('MP3')),
          findsOneWidget);

      // Verified check icon should NOT be present
      expect(find.byKey(const Key('verifiedCheck')), findsNothing);
    });

    testWidgets('MP3 entry with bitDepth=0 shows lossy quality badge "44.1k"',
        (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 0, sampleRate: 44100, bitrate: 320),
      );
      await tester.pumpWidget(buildTile(mp3Entry, bridge: bridge));
      await tester.pumpAndSettle();

      final qualityBadge = find.byKey(const Key('qualityBadge'));
      expect(qualityBadge, findsOneWidget);
      expect(
        find.descendant(of: qualityBadge, matching: find.text('44.1k')),
        findsOneWidget,
      );
    });

    testWidgets('no quality badge when bridge returns null', (tester) async {
      final bridge = _FakeBridge(null);
      await tester.pumpWidget(buildTile(flacEntry, bridge: bridge));
      await tester.pumpAndSettle();

      // Format badge still present
      expect(find.byKey(const Key('formatBadge')), findsOneWidget);
      // Quality badge absent
      expect(find.byKey(const Key('qualityBadge')), findsNothing);
    });
  });
}
