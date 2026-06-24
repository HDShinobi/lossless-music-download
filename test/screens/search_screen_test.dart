import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/search_provider.dart';
import 'package:lossless_music_download/screens/search_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fake backend bridge — records downloadByStrategy calls
// ---------------------------------------------------------------------------
class _FakeBackendBridge extends BackendBridge {
  final List<DownloadRequest> recorded = [];

  @override
  Future<void> setDownloadDirectory(String path) async {}

  @override
  Future<void> allowDownloadDir(String path) async {}

  @override
  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) async {
    recorded.add(req);
    return {};
  }

  @override
  Future<List<DownloadProgress>> getAllProgress() async => [];

  @override
  Future<void> cancelDownload(String itemId) async {}

  // enqueue seeds the download priority (reads then maybe sets it) before
  // downloading; stub both so the seed doesn't hit the real platform channel.
  @override
  Future<List<String>> getDownloadPriority() async => const [];

  @override
  Future<void> setDownloadPriority(List<String> ids) async {}
}

// ---------------------------------------------------------------------------
// Fake ExtensionsController
// ---------------------------------------------------------------------------
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _exts;
  _FakeExtensionsController(this._exts);

  @override
  Future<List<InstalledExtension>> build() async => _exts;
}

// ---------------------------------------------------------------------------
// Fake SearchNotifier — immediately returns the given list
// ---------------------------------------------------------------------------
class _FakeSearchNotifier extends SearchNotifier {
  final List<Track> _results;
  _FakeSearchNotifier(this._results);

  @override
  List<Track> build() => _results;

  @override
  Future<void> search(String q) async {
    state = AsyncData(_results);
  }
}

// ---------------------------------------------------------------------------
// Fake AskBeforeDownloadNotifier — allows setting state in tests
// ---------------------------------------------------------------------------
class _FakeAskBeforeDownloadNotifier extends AskBeforeDownloadNotifier {
  final bool _initialValue;

  _FakeAskBeforeDownloadNotifier(this._initialValue);

  @override
  bool build() => _initialValue;
}

// ---------------------------------------------------------------------------
// Helper: build SearchScreen with provider overrides
// ---------------------------------------------------------------------------
Widget buildSearchScreen({
  List<Track> results = const [],
  _FakeBackendBridge? bridge,
}) {
  final fakeBridge = bridge ?? _FakeBackendBridge();
  return ProviderScope(
    overrides: [
      backendBridgeProvider.overrideWithValue(fakeBridge),
      appDirsProvider.overrideWithValue(
        Future.value(('/fake/ext', '/fake/data')),
      ),
      downloadDirPathProvider.overrideWithValue(
        Future.value('/fake/downloads'),
      ),
      extensionsProvider.overrideWith(() => _FakeExtensionsController([])),
      searchProvider.overrideWith(() => _FakeSearchNotifier(results)),
      askBeforeDownloadProvider.overrideWith(
        () => AskBeforeDownloadNotifier(),
      ),
    ],
    child: MaterialApp(
      theme: appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const SearchScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Test tracks
// ---------------------------------------------------------------------------
const _track1 = Track(
  id: 'track-1',
  name: 'Song One',
  artists: 'Artist A',
  albumName: 'Album X',
);

const _track2 = Track(
  id: 'track-2',
  name: 'Song Two',
  artists: 'Artist B',
  albumName: 'Album Y',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('SearchScreen batch download', () {
    testWidgets('normal mode: askBefore=true shows picker then enqueues',
        (tester) async {
      final bridge = _FakeBackendBridge();
      // Need a download-capable extension so the sheet CTA is enabled.
      const fakeExt = InstalledExtension(
        id: 'ext-dl',
        name: 'ext-dl',
        displayName: 'Test Extension',
        version: '1.0.0',
        description: '',
        status: 'installed',
        types: [],
        permissions: [],
        enabled: true,
        hasMetadataProvider: true,
        hasDownloadProvider: true,
        hasLyricsProvider: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(bridge),
            appDirsProvider.overrideWithValue(
              Future.value(('/fake/ext', '/fake/data')),
            ),
            downloadDirPathProvider.overrideWithValue(
              Future.value('/fake/downloads'),
            ),
            extensionsProvider
                .overrideWith(() => _FakeExtensionsController([fakeExt])),
            searchProvider.overrideWith(() => _FakeSearchNotifier([_track1])),
            askBeforeDownloadProvider.overrideWith(() => _FakeAskBeforeDownloadNotifier(true)),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tapping the download icon shows the picker sheet when askBefore=true.
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();

      // Sheet CTA is enabled (source available) — confirm download.
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(bridge.recorded, hasLength(1));
    });

    testWidgets('long-press enters selection mode (shows selection bar)',
        (tester) async {
      await tester.pumpWidget(
        buildSearchScreen(results: [_track1, _track2]),
      );
      await tester.pumpAndSettle();

      // Long-press the first track tile
      await tester.longPress(find.text('Song One'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const Key('selectionClear')), findsOneWidget);
    });

    testWidgets(
        'selecting 2 tracks then tapping Download calls controller for both',
        (tester) async {
      final bridge = _FakeBackendBridge();
      await tester.pumpWidget(
        buildSearchScreen(results: [_track1, _track2], bridge: bridge),
      );
      await tester.pumpAndSettle();

      // Long-press track 1 to enter selection mode (track 1 selected)
      await tester.longPress(find.text('Song One'));
      await tester.pumpAndSettle();

      // Tap track 2 in selection mode to toggle selection
      await tester.tap(find.text('Song Two'));
      await tester.pumpAndSettle();

      // Tap the Download action button
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();

      expect(bridge.recorded, hasLength(2));
    });

    testWidgets('clear/X exits selection mode', (tester) async {
      await tester.pumpWidget(
        buildSearchScreen(results: [_track1]),
      );
      await tester.pumpAndSettle();

      // Enter selection mode
      await tester.longPress(find.text('Song One'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);

      // Tap the X / clear button
      await tester.tap(find.byKey(const Key('selectionClear')));
      await tester.pumpAndSettle();

      // Selection bar should be gone
      expect(find.text('1 selected'), findsNothing);
      expect(find.byKey(const Key('selectionClear')), findsNothing);
    });

    testWidgets('batch download shows snackbar', (tester) async {
      await tester.pumpWidget(
        buildSearchScreen(results: [_track1]),
      );
      await tester.pumpAndSettle();

      // Enter selection mode (1 track selected)
      await tester.longPress(find.text('Song One'));
      await tester.pumpAndSettle();

      // Tap Download
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text('Queued 1 for download'),
        findsOneWidget,
      );
    });

    testWidgets('askBefore=false: tapping download button enqueues immediately',
        (tester) async {
      final bridge = _FakeBackendBridge();
      const fakeExt = InstalledExtension(
        id: 'ext-dl',
        name: 'ext-dl',
        displayName: 'Test Extension',
        version: '1.0.0',
        description: '',
        status: 'installed',
        types: [],
        permissions: [],
        enabled: true,
        hasMetadataProvider: true,
        hasDownloadProvider: true,
        hasLyricsProvider: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(bridge),
            appDirsProvider.overrideWithValue(
              Future.value(('/fake/ext', '/fake/data')),
            ),
            downloadDirPathProvider.overrideWithValue(
              Future.value('/fake/downloads'),
            ),
            extensionsProvider
                .overrideWith(() => _FakeExtensionsController([fakeExt])),
            searchProvider.overrideWith(() => _FakeSearchNotifier([_track1])),
            askBeforeDownloadProvider.overrideWith(() => _FakeAskBeforeDownloadNotifier(false)),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When askBefore=false, tapping the download icon
      // should NOT show a bottom sheet; it should enqueue immediately.
      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();

      // No bottom sheet should appear (i.e., no "Download" button from sheet)
      expect(find.text('Download'), findsNothing);

      // Check that a download was enqueued
      expect(bridge.recorded, hasLength(1));

      // Check for the "Added to queue" snackbar
      expect(
        find.text('Added to queue'),
        findsOneWidget,
      );
    });
  });
}
