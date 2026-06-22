import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/audio_quality.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/verified_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/spectrogram_placeholder.dart';

// ---------------------------------------------------------------------------
// Fake bridge — returns a fixed AudioQuality for any path.
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  final AudioQuality? _quality;

  _FakeBridge(this._quality);

  @override
  Future<AudioQuality?> getAudioQuality(String path) async => _quality;
}

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

Widget buildVerifiedScreen(LibraryEntry entry, {BackendBridge? bridge}) {
  return ProviderScope(
    overrides: [
      if (bridge != null) backendBridgeProvider.overrideWithValue(bridge),
    ],
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
  group('VerifiedScreen — verified FLAC entry with real quality data', () {
    testWidgets('shows verified badge text', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      expect(find.text('Genuine lossless'), findsOneWidget);
    });

    testWidgets('shows format value in stats grid', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      // Format stat value — the actual format string
      expect(find.text('FLAC'), findsWidgets);
    });

    testWidgets('renders SpectrogramPlaceholder widget', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      expect(find.byType(SpectrogramPlaceholder), findsOneWidget);
    });

    testWidgets('shows real bit depth and sample rate from probe', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      // Bit depth and sample rate are now populated from the probe
      expect(find.text('24-bit'), findsOneWidget);
      expect(find.text('96.0 kHz'), findsOneWidget);
    });

    testWidgets('shows real bitrate from probe', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      expect(find.text('2304 kbps'), findsOneWidget);
    });

    testWidgets('shows serve title', (tester) async {
      final bridge = _FakeBridge(
        const AudioQuality(bitDepth: 24, sampleRate: 96000, bitrate: 2304),
      );
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
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

  group('VerifiedScreen — verified FLAC entry with null quality (loading/error)',
      () {
    testWidgets('shows em-dash placeholders when bridge returns null',
        (tester) async {
      final bridge = _FakeBridge(null);
      await tester.pumpWidget(buildVerifiedScreen(_flacVerified, bridge: bridge));
      await tester.pumpAndSettle();

      // All three quality stats show '—' when probe returns null
      expect(find.text('—'), findsAtLeastNWidgets(3));
    });
  });

  group('VerifiedScreen — unverified MP3 entry', () {
    testWidgets('shows unverified badge text', (tester) async {
      final bridge = _FakeBridge(null);
      await tester.pumpWidget(
          buildVerifiedScreen(_mp3Unverified, bridge: bridge));
      await tester.pumpAndSettle();

      expect(find.text('Not verified'), findsOneWidget);
    });

    testWidgets('does NOT show verified lossless text', (tester) async {
      final bridge = _FakeBridge(null);
      await tester.pumpWidget(
          buildVerifiedScreen(_mp3Unverified, bridge: bridge));
      await tester.pumpAndSettle();

      expect(find.text('Genuine lossless'), findsNothing);
    });
  });
}
