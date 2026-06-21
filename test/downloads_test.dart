import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/downloads_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/queue_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — records downloadByStrategy calls without hitting MethodChannel
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
}

const _kTestDir = '/test/downloads';

// ---------------------------------------------------------------------------
// Unit tests: DownloadController.start
// ---------------------------------------------------------------------------
void main() {
  group('DownloadController.start', () {
    test('builds DownloadRequest with correct fields', () async {
      final fake = _FakeBackendBridge();

      final container = ProviderContainer(
        overrides: [
          downloadDirPathProvider.overrideWithValue(Future.value(_kTestDir)),
          backendBridgeProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      const track = Track(
        id: 'tid1',
        name: 'My Song',
        artists: 'Artist Name',
        albumName: 'Album',
        isrc: 'US1234567890',
      );

      final controller = container.read(downloadControllerProvider);
      await controller.start(track);

      expect(fake.recorded, hasLength(1));
      final req = fake.recorded.first;
      expect(req.trackName, 'My Song');
      expect(req.outputDir, _kTestDir);
      expect(req.useExtensions, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests: QueueScreen
  // ---------------------------------------------------------------------------
  group('QueueScreen', () {
    Widget buildQueue({required List<DownloadProgress> items}) {
      return ProviderScope(
        overrides: [
          downloadsProvider.overrideWith(
            (ref) => Stream.value(items),
          ),
          // Provide a no-op bridge so cancel button doesn't crash
          backendBridgeProvider.overrideWithValue(_FakeBackendBridge()),
          // extensionsProvider needs a bridge too — override with empty list
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

    testWidgets('shows LinearProgressIndicator and cancel button for active download',
        (tester) async {
      await tester.pumpWidget(
        buildQueue(items: [
          const DownloadProgress(
            itemId: 'x',
            status: 'downloading',
            progress: 0.5,
            bytesReceived: 100,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('shows queueEmpty text when list is empty', (tester) async {
      await tester.pumpWidget(buildQueue(items: []));
      await tester.pumpAndSettle();

      expect(find.text('No downloads in queue.'), findsOneWidget);
    });
  });
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
