import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/downloads_provider.dart';
import 'package:lossless_music_download/services/app_log.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/native_download_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final previousPrint = debugPrint;
    try {
      await body(tester);
    } finally {
      debugPrint = previousPrint;
    }
  });
}

const _track = Track(
  id: 'logging',
  name: 'Song',
  artists: 'Artist',
  isrc: 'ISRC',
);
const _error = 'verification_required: complete browser challenge';

class _Bridge extends BackendBridge {
  final progress = StreamController<List<DownloadProgress>>.broadcast();
  Completer<Map<String, dynamic>> result = Completer();
  bool duplicate = false;

  @override
  Stream<List<DownloadProgress>> progressStream() => progress.stream;
  @override
  Future<void> setDownloadDirectory(String path) async {}
  @override
  Future<void> allowDownloadDir(String path) async {}
  @override
  Future<List<String>> getDownloadPriority() async => [];
  @override
  Future<Map<String, dynamic>> checkDuplicate(String dir, String isrc) async =>
      {'exists': duplicate, 'path': '/existing.flac'};
  @override
  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) =>
      result.future;
}

class _Worker extends NativeDownloadWorker {
  _Worker(this.available);
  final bool available;
  String? runId;
  NativeWorkerSnapshot? snapshot;
  @override
  bool get isAvailable => available;
  @override
  Future<void> start(
    List<Map<String, dynamic>> requests, {
    required String runId,
    Map<String, dynamic> settings = const {},
  }) async {
    this.runId = runId;
  }

  @override
  Future<NativeWorkerSnapshot?> getSnapshot() async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final status in ['done', 'failed']) {
    for (final progressFirst in [true, false]) {
      _test('$status logs once with progressFirst=$progressFirst', (
        tester,
      ) async {
        final rig = _Rig(native: true);
        addTearDown(rig.dispose);
        await rig.queue.enqueue(_track, service: 'soundcloud');
        await tester.pump();
        rig.bridge.progress.add([]);
        await tester.pump();
        expect(rig.worker.runId, isNotNull);
        final id = rig.entry.itemId;

        if (progressFirst) {
          rig.emit(status);
          await tester.pump();
          expect(rig.entry.status, status);
          expect(rig.lines(status), hasLength(1));
          if (status == 'done') {
            expect(rig.lines(status).single.message, contains('file=pending'));
            expect(rig.lines(status).single.message, contains('soundcloud'));
          }
        }
        rig.worker.snapshot = NativeWorkerSnapshot(
          runId: rig.worker.runId!,
          isRunning: false,
          items: [
            NativeWorkerItemState.fromJson({
              'item_id': id,
              'status': status,
              'file_path': '/final.flac',
              'resolved_service': 'soundcloud',
              'error': status == 'failed' ? _error : null,
              'service': 'qobuz-web',
            }),
          ],
        );
        await tester.pump(const Duration(milliseconds: 500));
        rig.emit(status);
        rig.emit(status);
        await tester.pump();
        expect(rig.lines(status), hasLength(1));
        expect(
          rig.lines(status).single.level,
          status == 'done' ? LogLevel.info : LogLevel.error,
        );
        if (status == 'done' && !progressFirst) {
          expect(rig.lines(status).single.message, contains('/final.flac'));
        }
        if (status == 'failed') {
          expect(rig.entry.error, _error);
          final warnings = rig.log.entries.where(
            (e) => e.level == LogLevel.warning,
          );
          expect(warnings, hasLength(1));
          expect(warnings.single.message, contains('qobuz-web'));
        }
      });
    }
  }

  for (final outcome in ['success', 'failure', 'exception', 'duplicate']) {
    _test('Dart $outcome logs exactly once', (tester) async {
      final rig = _Rig(native: false);
      addTearDown(rig.dispose);
      rig.bridge.duplicate = outcome == 'duplicate';
      await rig.queue.enqueue(_track, service: 'soundcloud');
      await tester.pump();
      if (outcome == 'exception') {
        rig.bridge.result.completeError(StateError('broken'));
      } else {
        rig.bridge.result.complete(
          outcome == 'failure'
              ? {'success': false, 'error': _error, 'service': 'qobuz-web'}
              : {
                  'success': true,
                  'file_path': '/final.flac',
                  'service': 'soundcloud',
                },
        );
      }
      await tester.pump();
      final failed = outcome == 'failure' || outcome == 'exception';
      expect(rig.entry.status, failed ? 'failed' : 'done');
      expect(rig.lines(failed ? 'failed' : 'done'), hasLength(1));
      if (!failed) {
        expect(
          rig.lines('done').single.message,
          contains(outcome == 'duplicate' ? '/existing.flac' : '/final.flac'),
        );
      }
      if (outcome == 'failure') {
        expect(
          rig.log.entries.where((e) => e.level == LogLevel.warning),
          hasLength(1),
        );
      }
    });
  }

  _test('progress failure then Dart failure logs once; retry logs again', (
    tester,
  ) async {
    final rig = _Rig(native: false);
    addTearDown(rig.dispose);
    await rig.queue.enqueue(_track, service: 'soundcloud');
    await tester.pump();
    final firstId = rig.entry.itemId;
    rig.emit('failed');
    await tester.pump();
    expect(rig.entry.status, 'failed');
    expect(rig.lines('failed'), hasLength(1));
    rig.bridge.result.complete({
      'success': false,
      'error': _error,
      'service': 'qobuz-web',
    });
    await tester.pump();
    expect(rig.lines('failed'), hasLength(1));
    expect(
      rig.log.entries.where((e) => e.level == LogLevel.warning),
      hasLength(1),
    );

    rig.bridge.result = Completer();
    rig.queue.retry(firstId);
    await tester.pump();
    expect(rig.entry.itemId, isNot(firstId));
    rig.emit('failed');
    await tester.pump();
    rig.bridge.result.complete({
      'success': false,
      'error': _error,
      'service': 'qobuz-web',
    });
    await tester.pump();
    expect(rig.lines('failed'), hasLength(2));
    expect(
      rig.log.entries.where((e) => e.level == LogLevel.warning),
      hasLength(2),
    );
  });

  _test('automatic rate-limit retry logs failure for each attempt', (
    tester,
  ) async {
    final rig = _Rig(native: true);
    addTearDown(rig.dispose);
    await rig.queue.enqueue(_track, service: 'soundcloud');
    await tester.pump();
    final id = rig.entry.itemId;
    rig.worker.snapshot = NativeWorkerSnapshot(
      runId: rig.worker.runId!,
      isRunning: false,
      items: [
        NativeWorkerItemState.fromJson({
          'item_id': id,
          'status': 'failed',
          'error': 'HTTP 429 Too Many Requests',
          'retry_after_seconds': 5,
        }),
      ],
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.lines('failed'), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    expect(rig.entry.itemId, id);
    expect(rig.entry.status, 'queued');
    rig.worker.snapshot = NativeWorkerSnapshot(
      runId: rig.worker.runId!,
      isRunning: false,
      items: [
        NativeWorkerItemState.fromJson({
          'item_id': id,
          'status': 'failed',
          'error': 'unavailable',
        }),
      ],
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.lines('failed'), hasLength(2));
  });

  _test('progress completion then Dart result logs once', (tester) async {
    final rig = _Rig(native: false);
    addTearDown(rig.dispose);
    await rig.queue.enqueue(_track, service: 'soundcloud');
    await tester.pump();
    rig.emit('done');
    await tester.pump();
    expect(rig.lines('done'), hasLength(1));
    rig.bridge.result.complete({'success': true, 'file_path': '/final.flac'});
    await tester.pump();
    expect(rig.lines('done'), hasLength(1));
  });
}

class _Rig {
  _Rig({required bool native}) : worker = _Worker(native) {
    SharedPreferences.setMockInitialValues({});
    debugPrint = (message, {wrapWidth}) {
      if (message != null) log.capturePrint(message);
    };
    container = ProviderContainer(
      overrides: [
        downloadsProvider.overrideWith((ref) => bridge.progress.stream),
        backendBridgeProvider.overrideWithValue(bridge),
        downloadDirPathProvider.overrideWithValue(
          Future.value('/fake/downloads'),
        ),
        nativeDownloadWorkerProvider.overrideWithValue(worker),
      ],
    );
    container.listen(downloadQueueProvider, (_, next) {});
    queue = container.read(downloadQueueProvider.notifier);
  }
  final previousPrint = debugPrint;
  final log = AppLog();
  final bridge = _Bridge();
  final _Worker worker;
  late final ProviderContainer container;
  late final DownloadQueueController queue;
  DownloadEntry get entry => container.read(downloadQueueProvider).single;
  Iterable<LogEntry> lines(String status) => log.entries.where(
    (e) => e.message.startsWith(status == 'done' ? 'Completed ' : 'Failed '),
  );
  void emit(String status) => bridge.progress.add([
    DownloadProgress(
      itemId: entry.itemId,
      status: status,
      progress: 1,
      bytesReceived: 100,
    ),
  ]);
  Future<void> dispose() async {
    container.dispose();
    await bridge.progress.close();
    debugPrint = previousPrint;
  }
}
