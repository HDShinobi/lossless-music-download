import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lossless_music_download/services/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/native_download_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnusedBridge extends BackendBridge {
  @override
  Future<void> setDownloadDirectory(String path) async {}
  @override
  Future<void> allowDownloadDir(String path) async {}
}

class _FakeNativeWorker extends NativeDownloadWorker {
  final List<List<Map<String, dynamic>>> startedBatches = [];
  NativeWorkerSnapshot? snapshotToReturn;

  /// When set, every started item is reported with this state instead of
  /// the default 'done' — used to simulate failures.
  NativeWorkerItemState Function(String itemId)? failItemsWith;

  @override
  bool get isAvailable => true;

  @override
  Future<void> start(List<Map<String, dynamic>> requests, {required String runId}) async {
    startedBatches.add(requests);
    snapshotToReturn = NativeWorkerSnapshot(
      runId: runId,
      isRunning: false,
      items: requests
          .map((r) => failItemsWith?.call(r['item_id'] as String) ??
              NativeWorkerItemState(
                itemId: r['item_id'] as String,
                status: 'done',
                progress: 1.0,
                bytesReceived: 100,
                bytesTotal: 100,
              ))
          .toList(),
    );
  }

  @override
  Future<NativeWorkerSnapshot?> getSnapshot() async => snapshotToReturn;

  @override
  Future<void> stop() async {}
}

const _track = Track(id: 'native-track', name: 'Native Song', artists: 'Native Artist');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('native completion logs the resolved service and final path once', () async {
    final log = AppLog();
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) log.capturePrint(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    final worker = _FakeNativeWorker()
      ..failItemsWith = (id) => NativeWorkerItemState.fromJson({
        'item_id': id,
        'status': 'done',
        'resolved_service': 'qobuz-web',
        'file_path': '/fake/final.flac',
      });
    final container = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(_UnusedBridge()),
      downloadDirPathProvider.overrideWithValue(Future.value('/fake/downloads')),
      nativeDownloadWorkerProvider.overrideWithValue(worker),
    ]);
    addTearDown(container.dispose);
    await container.read(downloadQueueProvider.notifier).enqueue(_track);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final success = log.entries.where((e) => e.message.contains('/fake/final.flac'));
    expect(success, hasLength(1));
    expect(success.single.level, LogLevel.info);
    expect(success.single.message, contains('qobuz-web'));
  });

  test('enqueue hands the item to the native worker when available', () async {
    final nativeWorker = _FakeNativeWorker();
    final container = ProviderContainer(
      overrides: [
        backendBridgeProvider.overrideWithValue(_UnusedBridge()),
        downloadDirPathProvider.overrideWithValue(Future.value('/fake/downloads')),
        nativeDownloadWorkerProvider.overrideWithValue(nativeWorker),
      ],
    );
    addTearDown(container.dispose);

    await container.read(downloadQueueProvider.notifier).enqueue(Track.fromJson({
      'id': 'native-track', 'name': 'Native Song', 'artists': 'Native Artist',
      'album_name': 'Album', 'track_number': 1, 'disc_number': 2, 'total_discs': 2,
      'explicit': true, 'upc': '00123', 'album_type': 'album',
      'deezer_id': '42', 'playlistPosition': 3,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(nativeWorker.startedBatches, hasLength(1));
    final request = nativeWorker.startedBatches.first.single;
    expect(request['track_name'], 'Native Song');
    expect(request['artist_name'], 'Native Artist');
    final payload = jsonDecode(request['request_json'] as String) as Map<String, dynamic>;
    expect(payload['output_dir'], '/fake/downloads/Native Artist/Album');
    expect(payload['filename_format'], '{disc}-{track}. {title}');
    expect(payload['disc_number'], 2);
    expect(payload['explicit'], true);
    expect(payload['upc'], '00123');
    expect(payload['album_type'], 'album');
    expect(payload['deezer_id'], '42');
    expect(payload['playlist_position'], 3);
    expect(payload['cover_max_dimension'], 0);
    expect(payload['artist_tag_mode'], 'joined');
    expect(payload.containsKey('metadata_separators'), false);
    expect(payload.containsKey('album_folder_template'), false);

    final state = container.read(downloadQueueProvider);
    expect(state.first.status, 'done');
    expect(state.first.progress, 1.0);
  });

  test('native payload uses custom templates and tagging preferences', () async {
    final worker = _FakeNativeWorker();
    final c = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(_UnusedBridge()),
      downloadDirPathProvider.overrideWithValue(Future.value('/fake/downloads')),
      nativeDownloadWorkerProvider.overrideWithValue(worker),
    ]);
    addTearDown(c.dispose);
    await c.read(filenameTemplateProvider.notifier).set('{title} - {artist}');
    await c.read(albumFolderTemplateProvider.notifier).set('{album} ({year})');
    await c.read(artistTagModeProvider.notifier).set('primary');
    await c.read(metadataSeparatorsProvider.notifier).setField('genre', ' / ');
    await c.read(downloadQueueProvider.notifier).enqueue(const Track(
      id: 'custom', name: 'Song', artists: 'Artist', albumName: 'Album',
      releaseDate: '2026-11-07', discNumber: 2, totalDiscs: 2));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final json = jsonDecode(worker.startedBatches.single.single['request_json'] as String);
    expect(json['output_dir'], '/fake/downloads/Album (2026)');
    expect(json['filename_format'], '{disc}-{title} - {artist}');
    expect(json['artist_tag_mode'], 'primary');
    expect(json['metadata_separators']['genre'], ' / ');
    expect(json.containsKey('album_folder_template'), false);
  });

  test('NativeWorkerItemState.fromJson parses the verification service', () {
    final item = NativeWorkerItemState.fromJson({
      'item_id': 'dl_1',
      'status': 'failed',
      'progress': 0.0,
      'bytes_received': 0,
      'bytes_total': 0,
      'error': 'Download failed: VERIFY_REQUIRED',
      'service': 'qobuz-web',
    });
    expect(item.service, 'qobuz-web');
  });

  test('failed native item propagates verification service to the entry',
      () async {
    final nativeWorker = _FakeNativeWorker()
      ..failItemsWith = (itemId) => NativeWorkerItemState(
            itemId: itemId,
            status: 'failed',
            progress: 0,
            bytesReceived: 0,
            bytesTotal: 0,
            error: 'Download failed: VERIFY_REQUIRED',
            service: 'qobuz-web',
          );
    final container = ProviderContainer(
      overrides: [
        backendBridgeProvider.overrideWithValue(_UnusedBridge()),
        downloadDirPathProvider.overrideWithValue(Future.value('/fake/downloads')),
        nativeDownloadWorkerProvider.overrideWithValue(nativeWorker),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(downloadQueueProvider.notifier)
        .enqueue(_track, service: 'amazon');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final entry = container.read(downloadQueueProvider).first;
    expect(entry.status, 'failed');
    expect(entry.service, 'amazon');
    expect(entry.verificationService, 'qobuz-web');
  });

  test('done native item propagates resolved service to the entry', () async {
    final nativeWorker = _FakeNativeWorker()
      ..failItemsWith = (itemId) => NativeWorkerItemState(
            itemId: itemId,
            status: 'done',
            progress: 1.0,
            bytesReceived: 100,
            bytesTotal: 100,
            resolvedService: 'qobuz',
          );
    final container = ProviderContainer(
      overrides: [
        backendBridgeProvider.overrideWithValue(_UnusedBridge()),
        downloadDirPathProvider.overrideWithValue(Future.value('/fake/downloads')),
        nativeDownloadWorkerProvider.overrideWithValue(nativeWorker),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(downloadQueueProvider.notifier)
        .enqueue(_track, service: 'amazon');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final entry = container.read(downloadQueueProvider).first;
    expect(entry.status, 'done');
    expect(entry.resolvedService, 'qobuz');
  });
}
