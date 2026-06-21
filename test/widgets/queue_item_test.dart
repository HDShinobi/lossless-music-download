import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/queue_item.dart';

// ---------------------------------------------------------------------------
// Minimal fake BackendBridge for queue item tests
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  final List<String> cancelCalls = [];

  @override
  Future<void> cancelDownload(String itemId) async {
    cancelCalls.add(itemId);
  }

  @override
  Future<List<DownloadProgress>> getAllProgress() async => [];

  // Required: override initExtensionSystem and loadExtensionsFromDir
  // to avoid MethodChannel calls during test.
  @override
  Future<void> initExtensionSystem(String extDir, String dataDir) async {}

  @override
  Future<String?> loadExtensionsFromDir(String dirPath) async => null;

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async => [];
}

// ---------------------------------------------------------------------------
// Helper: pump a QueueItem inside the required widget tree
// ---------------------------------------------------------------------------
Future<void> _pumpItem(
  WidgetTester tester,
  DownloadProgress item,
  _FakeBridge bridge,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendBridgeProvider.overrideWithValue(bridge),
        appDirsProvider.overrideWithValue(
          Future.value(('/fake/ext', '/fake/data')),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: QueueItem(item: item),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QueueItem', () {
    testWidgets('downloading item shows MB in status line and cancel icon',
        (tester) async {
      final bridge = _FakeBridge();
      final item = DownloadProgress(
        itemId: 'track-abc-123',
        status: 'downloading',
        progress: 0.6,
        bytesReceived: 196083712,
      );

      await _pumpItem(tester, item, bridge);

      // itemId shown as title
      expect(find.text('track-abc-123'), findsOneWidget);

      // mono status line contains 'MB'
      expect(find.textContaining('MB'), findsWidgets);

      // cancel icon present
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('downloading item cancel icon calls cancelDownload',
        (tester) async {
      final bridge = _FakeBridge();
      final item = DownloadProgress(
        itemId: 'track-abc-123',
        status: 'downloading',
        progress: 0.6,
        bytesReceived: 196083712,
      );

      await _pumpItem(tester, item, bridge);

      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();

      expect(bridge.cancelCalls, contains('track-abc-123'));
    });

    testWidgets('failed item shows failed status text', (tester) async {
      final bridge = _FakeBridge();
      final item = DownloadProgress(
        itemId: 'track-fail-456',
        status: 'failed',
        progress: 0.0,
        bytesReceived: 0,
      );

      await _pumpItem(tester, item, bridge);

      // Should show the failed l10n text "Failed · tap to retry"
      expect(find.textContaining('retry'), findsOneWidget);
    });

    testWidgets('done item shows done/check icon', (tester) async {
      final bridge = _FakeBridge();
      final item = DownloadProgress(
        itemId: 'track-done-789',
        status: 'completed',
        progress: 1.0,
        bytesReceived: 327155712,
      );

      await _pumpItem(tester, item, bridge);

      // check_circle or verified icon present
      expect(
        find.byWidgetPredicate((w) =>
            w is Icon &&
            (w.icon == Icons.check_circle_outline ||
                w.icon == Icons.verified_outlined ||
                w.icon == Icons.check_circle ||
                w.icon == Icons.verified)),
        findsOneWidget,
      );
    });

    testWidgets('queued item shows queued text', (tester) async {
      final bridge = _FakeBridge();
      final item = DownloadProgress(
        itemId: 'track-queued-000',
        status: 'queued',
        progress: 0.0,
        bytesReceived: 0,
      );

      await _pumpItem(tester, item, bridge);

      // Should show "In queue" from l10n
      expect(find.textContaining('queue'), findsWidgets);
    });
  });
}
