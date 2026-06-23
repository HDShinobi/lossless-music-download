import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/downloads_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/queue_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

class _FakeBackendBridge extends BackendBridge {
  @override
  Future<void> setDownloadDirectory(String path) async {}

  @override
  Future<void> allowDownloadDir(String path) async {}

  @override
  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) async =>
      {};

  @override
  Future<List<DownloadProgress>> getAllProgress() async => [];

  @override
  Future<void> cancelDownload(String itemId) async {}
}

void main() {
  // ---------------------------------------------------------------------------
  // Widget tests: QueueScreen — driven by downloadQueueProvider
  // ---------------------------------------------------------------------------
  group('QueueScreen', () {
    const downloading = DownloadEntry(
      track: Track(id: 'x', name: 'Test Track', artists: 'Artist'),
      itemId: 'x',
      status: 'downloading',
      progress: 0.5,
      bytesReceived: 104857600, // 100 MB
    );

    Widget buildQueue({required List<DownloadEntry> entries}) {
      return ProviderScope(
        overrides: [
          // Override the persistent queue with a fixed list.
          downloadQueueProvider.overrideWith(() => _FixedQueueController(entries)),
          // Keep the poll alive but return nothing (entries drive display).
          downloadsProvider.overrideWith((ref) => Stream.value([])),
          // Provide a no-op bridge so cancel/dismiss buttons don't crash.
          backendBridgeProvider.overrideWithValue(_FakeBackendBridge()),
          // extensionsProvider needs a bridge too.
          extensionsProvider.overrideWith(
            () => _FakeExtensionsController([]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: QueueScreen(),
        ),
      );
    }

    testWidgets('shows progress card with cancel button for active download',
        (tester) async {
      await tester.pumpWidget(buildQueue(entries: [downloading]));
      await tester.pumpAndSettle();

      // QueueItem uses a brand card with a cancel icon for 'downloading' state.
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.textContaining('MB'), findsWidgets);
    });

    testWidgets('shows queueEmpty text when list is empty', (tester) async {
      await tester.pumpWidget(buildQueue(entries: []));
      await tester.pumpAndSettle();

      expect(find.text('No downloads yet.'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixed-state queue controller — always returns the provided entries list
// ---------------------------------------------------------------------------
class _FixedQueueController extends DownloadQueueController {
  final List<DownloadEntry> _entries;
  _FixedQueueController(this._entries);

  @override
  List<DownloadEntry> build() {
    // Do not call super.build() — we don't want the listener wired up.
    return _entries;
  }
}

// ---------------------------------------------------------------------------
// Fake ExtensionsController for widget tests
// ---------------------------------------------------------------------------
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _list;
  _FakeExtensionsController(this._list);

  @override
  Future<List<InstalledExtension>> build() async => _list;
}
