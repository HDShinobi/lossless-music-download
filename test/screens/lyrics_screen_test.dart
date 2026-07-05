import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/lyrics_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake BackendBridge — returns a fixed LRC/sentinel string, no MethodChannel.
// ---------------------------------------------------------------------------
class _FakeLyricsBridge extends BackendBridge {
  _FakeLyricsBridge(this._lrc);
  final String _lrc;

  @override
  Future<String> getLyricsLRC({
    String spotifyId = '',
    required String trackName,
    required String artistName,
    String filePath = '',
    int durationMs = 0,
  }) async =>
      _lrc;
}

const _fakeEntry = LibraryEntry(
  path: '/fake/track.flac',
  name: 'track.flac',
  title: 'Test Track',
  sizeBytes: 0,
  artistName: 'Test Artist',
  format: 'FLAC',
  verified: true,
);

Future<void> _pumpLyricsScreen(WidgetTester tester, String lrc) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendBridgeProvider.overrideWithValue(_FakeLyricsBridge(lrc)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: LyricsScreen(entry: _fakeEntry),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LyricsScreen', () {
    testWidgets('renders synced lyric lines', (tester) async {
      await _pumpLyricsScreen(
        tester,
        '[00:01.00]hello\n[00:02.00]world',
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
    });

    testWidgets('shows lyricsNotFound empty state', (tester) async {
      await _pumpLyricsScreen(tester, '');

      expect(
        find.text('No lyrics found for this track.'),
        findsOneWidget,
      );
    });

    testWidgets('shows lyricsInstrumental state, never the raw sentinel',
        (tester) async {
      await _pumpLyricsScreen(tester, '[instrumental:true]');

      expect(find.text('Instrumental track'), findsOneWidget);
      expect(find.text('[instrumental:true]'), findsNothing);
    });
  });
}
