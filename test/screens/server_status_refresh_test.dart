import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/server_provider.dart';
import 'package:lossless_music_download/screens/server_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

class _Bridge extends BackendBridge {
  ServerStatus status = const ServerStatus(
    running: true,
    url: 'http://10.0.0.2:8200',
  );
  int reads = 0;
  bool failStart = false;

  @override
  Future<ServerStatus> getMediaServerStatus() async {
    reads++;
    return status;
  }

  @override
  Future<ServerStatus> startMediaServer(String rootDir, String name) async {
    if (failStart) throw Exception('port already in use');
    return status;
  }
}

class _StopRaceBridge extends _Bridge {
  final stopPending = Completer<void>();
  final readPending = Completer<ServerStatus>();
  bool delayReads = false;

  @override
  Future<ServerStatus> getMediaServerStatus() =>
      delayReads ? readPending.future : super.getMediaServerStatus();

  @override
  Future<void> stopMediaServer() => stopPending.future;
}

void main() {
  test('poll begun during stop cannot restore stale running status', () async {
    final bridge = _StopRaceBridge()..status = ServerStatus.stopped;
    final container = ProviderContainer(
      overrides: [backendBridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    await container.read(serverProvider.future);
    bridge.delayReads = true;
    final controller = container.read(serverProvider.notifier);
    final stop = controller.stop();
    final poll = controller.refreshStatus();
    bridge.stopPending.complete();
    await stop;
    bridge.readPending.complete(const ServerStatus(running: true));
    await poll;
    expect(container.read(serverProvider).value?.running, isFalse);
  });

  testWidgets(
    'screen refreshes spontaneous server stop without loading spinner',
    (tester) async {
      final bridge = _Bridge();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(bridge),
            downloadDirProvider.overrideWith((_) async => '/music'),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ServerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stop server'), findsOneWidget);
      bridge.status = ServerStatus.stopped;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(bridge.reads, greaterThanOrEqualTo(2));
      expect(find.text('Start server'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final readsAfterUnmount = bridge.reads;
      await tester.pump(const Duration(seconds: 5));
      expect(bridge.reads, readsAfterUnmount);
    },
  );

  testWidgets(
    'failed start reason survives a poll and Start remains tappable',
    (tester) async {
      final bridge = _Bridge()
        ..status = ServerStatus.stopped
        ..failStart = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(bridge),
            downloadDirProvider.overrideWith((_) async => '/music'),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ServerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start server'));
      await tester.pumpAndSettle();
      expect(find.textContaining('port already in use'), findsOneWidget);
      expect(find.text('Start server'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.textContaining('port already in use'), findsOneWidget);
      expect(find.text('Start server'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      bridge
        ..failStart = false
        ..status = const ServerStatus(running: true, url: 'http://10.0.0.2:8200');
      await tester.tap(find.text('Start server'));
      await tester.pumpAndSettle();
      expect(find.textContaining('port already in use'), findsNothing);
      expect(find.text('Stop server'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
