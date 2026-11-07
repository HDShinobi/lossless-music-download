import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/history_database.dart';
import 'package:lossless_music_download/services/native_download_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const song = Track(
  id: 'qobuz:42',
  source: 'qobuz',
  name: 'Song',
  artists: 'Artist',
);

class CountingHistoryDatabase extends HistoryDatabase {
  int prechecks = 0;
  CountingHistoryDatabase({required super.path, super.factory});
  @override
  Future<List<HistoryEntry?>> findBatch(
    List<Track> tracks, {
    bool strict = false,
  }) {
    prechecks++;
    return super.findBatch(tracks, strict: strict);
  }
}

class SilentWorker extends Worker {
  SilentWorker(super.path);
  @override
  Future<NativeWorkerSnapshot?> getSnapshot() async => null;
}

class Bridge extends BackendBridge {
  Map<String, dynamic> result = {};
  int downloads = 0;
  Completer<Map<String, dynamic>>? pending;
  String? indexedPath;
  List<Map<String, dynamic>> scan = [];
  int scans = 0;
  @override
  Future<Map<String, dynamic>> checkDuplicate(
    String outputDir,
    String isrc,
  ) async => {
    'exists': indexedPath != null,
    if (indexedPath != null) 'filepath': indexedPath,
  };
  @override
  Future<void> setLibraryCoverCacheDir(String path) async {}
  @override
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String path) async {
    scans++;
    return scan;
  }

  final progress = StreamController<List<DownloadProgress>>.broadcast();
  @override
  Stream<List<DownloadProgress>> progressStream() => progress.stream;
  @override
  Future<void> setDownloadDirectory(String path) async {}
  @override
  Future<void> allowDownloadDir(String path) async {}
  @override
  Future<List<String>> getDownloadPriority() async => [];
  @override
  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) async {
    downloads++;
    return pending == null ? result : await pending!.future;
  }
}

class Worker extends NativeDownloadWorker {
  final String path;
  String? run;
  String? item;
  bool withPath = false;
  String? error;
  int starts = 0;
  Map<String, dynamic>? lastRequest;
  Worker(this.path);
  @override
  bool get isAvailable => true;
  @override
  Future<void> start(
    List<Map<String, dynamic>> requests, {
    required String runId,
    Map<String, dynamic> settings = const {},
  }) async {
    starts++;
    lastRequest =
        jsonDecode(requests.single['request_json'] as String)
            as Map<String, dynamic>;
    run = runId;
    item = requests.single['item_id'] as String;
  }

  @override
  Future<NativeWorkerSnapshot?> getSnapshot() async => NativeWorkerSnapshot(
    runId: run!,
    isRunning: !withPath,
    items: [
      NativeWorkerItemState(
        itemId: item!,
        status: error == null ? 'done' : 'failed',
        error: error,
        progress: 1,
        bytesReceived: 5,
        bytesTotal: 5,
        filePath: withPath ? path : null,
        resolvedService: 'tidal',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late CountingHistoryDatabase db;
  late Bridge bridge;
  late ProviderContainer container;
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 250));
  Future<void> waitFor(FutureOr<bool> Function() condition, {int seconds = 5}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for queue/history');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  ProviderContainer setup({Worker? worker}) => ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) async => db),
      libraryCoverCacheDirProvider.overrideWithValue(Future.value(dir.path)),
      backendBridgeProvider.overrideWithValue(bridge),
      downloadDirPathProvider.overrideWithValue(Future.value(dir.path)),
      if (worker != null)
        nativeDownloadWorkerProvider.overrideWithValue(worker),
    ],
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'embed_metadata': false,
      'embed_lyrics': false,
      'embed_cover': false,
    });
    dir = await Directory.systemTemp.createTemp('history_queue_');
    db = CountingHistoryDatabase(
      path: '${dir.path}/history.db',
      factory: databaseFactoryFfi,
    );
    bridge = Bridge();
  });
  tearDown(() async {
    container.dispose();
    await bridge.progress.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  test('native startup fallback reuses history admission', () async {
    bridge.result = {'success': true};
    container = setup(worker: SilentWorker('${dir.path}/new.flac'));
    await container.read(downloadQueueProvider.notifier).enqueue(song);
    await waitFor(() => bridge.downloads == 1, seconds: 40);
    expect(db.prechecks, 1);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test(
    'Dart fallback records final result path and existing-file outcomes',
    () async {
      final file = await File('${dir.path}/final.flac').writeAsString('audio');
      bridge.result = {
        'success': true,
        'file_path': file.path,
        'service': 'tidal',
      };
      container = setup();
      final queue = container.read(downloadQueueProvider.notifier);
      await queue.enqueue(song, quality: 'FLAC');
      await waitFor(() async => (await db.list()).isNotEmpty);
      expect((await db.list()).single.filePath, file.path);
      expect((await db.list()).single.service, 'tidal');
      await db.remove((await db.list()).single.id);
      bridge.result = {
        'success': false,
        'error': 'resolve album folder: open ${file.path}: file exists',
      };
      await queue.enqueue(song);
      await waitFor(() async => (await db.list()).isNotEmpty);
      expect((await db.list()).single.filePath, file.path);
      expect(
        container.read(downloadQueueProvider).first.alreadyInLibrary,
        isTrue,
      );
    },
  );
  test(
    'native completion without path waits and records the later final snapshot once',
    () async {
      final file = await File('${dir.path}/native.flac').writeAsString('audio');
      final worker = Worker(file.path);
      container = setup(worker: worker);
      await container.read(downloadQueueProvider.notifier).enqueue(song);
      await waitFor(
        () => container.read(downloadQueueProvider).single.status == 'done',
      );
      expect(await db.list(), isEmpty);
      expect(container.read(downloadQueueProvider).single.status, 'done');
      worker.withPath = true;
      await waitFor(() async => (await db.list()).isNotEmpty);
      final row = (await db.list()).single;
      expect(row.filePath, file.path);
      expect(row.service, 'tidal');
      expect(row.fileSize, 5);
      expect(bridge.downloads, 0);
    },
  );
  test(
    'native late path is recorded after the completed queue row is cleared',
    () async {
      final file = await File('${dir.path}/late.flac').writeAsString('audio');
      final worker = Worker(file.path);
      container = setup(worker: worker);
      final queue = container.read(downloadQueueProvider.notifier);
      await queue.enqueue(song);
      await waitFor(
        () => container.read(downloadQueueProvider).single.status == 'done',
      );
      queue.clearCompleted();
      expect(container.read(downloadQueueProvider), isEmpty);
      worker.withPath = true;
      await waitFor(() async => (await db.list()).isNotEmpty);
      expect((await db.list()).single.filePath, file.path);
    },
  );
  test(
    'Dart late result is recorded after progress completion is cleared',
    () async {
      final file = await File(
        '${dir.path}/late-dart.flac',
      ).writeAsString('audio');
      bridge.pending = Completer();
      container = setup();
      container.listen(downloadQueueProvider, (_, _) {});
      final queue = container.read(downloadQueueProvider.notifier);
      await queue.enqueue(song);
      await waitFor(() => bridge.downloads == 1);
      final id = container.read(downloadQueueProvider).single.itemId;
      bridge.progress.add([
        DownloadProgress(
          itemId: id,
          status: 'completed',
          progress: 1,
          bytesReceived: 5,
        ),
      ]);
      await waitFor(
        () => container.read(downloadQueueProvider).single.status == 'done',
      );
      queue.clearCompleted();
      expect(container.read(downloadQueueProvider), isEmpty);
      bridge.pending!.complete({
        'success': true,
        'file_path': file.path,
        'service': 'tidal',
      });
      await waitFor(() async => (await db.list()).isNotEmpty);
      expect((await db.list()).single.filePath, file.path);
    },
  );
  test(
    'native IndexCache skip records the existing path without starting worker',
    () async {
      final file = await File(
        '${dir.path}/indexed.flac',
      ).writeAsString('audio');
      bridge.indexedPath = file.path;
      final worker = Worker(file.path)..withPath = true;
      container = setup(worker: worker);
      await container
          .read(downloadQueueProvider.notifier)
          .enqueue(
            const Track(
              id: 'indexed',
              name: 'Song',
              artists: 'Artist',
              isrc: 'USABC1234567',
            ),
          );
      await waitFor(() async => (await db.list()).isNotEmpty);
      expect(worker.starts, 0);
      expect((await db.list()).single.filePath, file.path);
      expect(
        container.read(downloadQueueProvider).single.alreadyInLibrary,
        isTrue,
      );
    },
  );
  test('native engine file-exists error upserts history', () async {
    final file = await File(
      '${dir.path}/collision.flac',
    ).writeAsString('audio');
    final worker = Worker(file.path)
      ..withPath = true
      ..error = 'resolve album folder: open ${file.path}: file exists';
    container = setup(worker: worker);
    await container.read(downloadQueueProvider.notifier).enqueue(song);
    await waitFor(() async => (await db.list()).isNotEmpty);
    expect((await db.list()).single.filePath, file.path);
    expect(
      container.read(downloadQueueProvider).single.alreadyInLibrary,
      isTrue,
    );
  });
  test(
    'library scan backfills old files once and repairs moved history before seeding',
    () async {
      final file = await File('${dir.path}/old.flac').writeAsString('audio');
      bridge.scan = [
        {
          'filePath': file.path,
          'trackName': 'Song',
          'artistName': 'Artist',
          'albumName': 'Album',
          'duration': 180,
          'isrc': 'USABC1234567',
        },
      ];
      container = setup();
      await container.read(libraryProvider.future);
      final original = (await db.list()).single;
      expect(original.fileSize, 5);
      expect(original.track.isrc, 'USABC1234567');
      expect(await db.find(song), isNotNull);
      final moved = '${dir.path}/album/old.flac';
      await Directory('${dir.path}/album').create();
      await file.rename(moved);
      bridge.scan.single['filePath'] = moved;
      container.invalidate(libraryProvider);
      await container.read(libraryProvider.future);
      expect((await db.list()).single.filePath, moved);
      await db.remove(original.id);
      container.invalidate(libraryProvider);
      await container.read(libraryProvider.future);
      expect(await db.list(), isEmpty);
    },
  );
  test(
    'first library scan continues backfill beyond its first bounded page',
    () async {
      for (var i = 0; i < 260; i++) {
        final file = await File(
          '${dir.path}/old-$i.flac',
        ).writeAsString('audio');
        bridge.scan.add({
          'filePath': file.path,
          'trackName': 'Old $i',
          'artistName': 'Artist',
        });
      }
      container = setup();
      await container.read(libraryProvider.future);
      await waitFor(() async => (await db.list(limit: 300)).length == 260);
      container.invalidate(libraryProvider);
      await container.read(libraryProvider.future);
      expect(await db.list(limit: 300), hasLength(260));
    },
  );
  test(
    'downloaded indicators do not collide for equal IDs from different providers',
    () async {
      const qobuz = Track(
        id: '42',
        source: 'qobuz',
        name: 'One',
        artists: 'Artist',
      );
      const tidal = Track(
        id: '42',
        source: 'tidal',
        name: 'Other',
        artists: 'Else',
      );
      final file = await File('${dir.path}/qobuz.flac').writeAsString('audio');
      await db.upsert(
        HistoryEntry(
          id: 'one',
          track: qobuz,
          service: 'qobuz',
          filePath: file.path,
          downloadedAt: DateTime.now(),
        ),
      );
      container = setup();
      final matches = await container.read(
        downloadedTracksProvider(HistoryLookupBatch([qobuz, tidal])).future,
      );
      expect(matches, contains(historyLookupKey(qobuz)));
      expect(matches, isNot(contains(historyLookupKey(tidal))));
    },
  );
  for (final native in [false, true]) {
    for (final seeded in [false, true]) {
      test(
        'same title does not block ${native ? "native" : "Dart"} download (scan=$seeded)',
        () async {
          const explicit = Track(
            id: 'qobuz:1',
            source: 'qobuz',
            name: 'Song',
            artists: 'Artist',
            albumName: 'Album',
            durationMs: 180000,
            isrc: 'EXPLICIT',
            explicit: true,
          );
          final file = await File(
            '${dir.path}/explicit.flac',
          ).writeAsString('audio');
          final row = HistoryEntry(
            id: 'old',
            track: seeded ? song : explicit,
            service: 'qobuz',
            filePath: file.path,
            downloadedAt: DateTime.now(),
          );
          if (seeded) {
            await db.backfill(dir.path, [row]);
          } else {
            await db.upsert(row);
          }
          final worker = Worker(file.path)..withPath = true;
          bridge.result = {'success': true, 'file_path': file.path};
          container = setup(worker: native ? worker : null);
          await container
              .read(downloadQueueProvider.notifier)
              .enqueue(
                const Track(
                  id: 'qobuz:2',
                  source: 'qobuz',
                  name: 'Song',
                  artists: 'Artist',
                  albumName: 'Album',
                  durationMs: 180000,
                  isrc: 'CLEAN',
                  explicit: false,
                ),
              );
          await waitFor(() => (native ? worker.starts : bridge.downloads) == 1);
          expect(native ? worker.starts : bridge.downloads, 1);
          expect(
            container.read(downloadQueueProvider).single.alreadyInLibrary,
            isFalse,
          );
        },
      );
    }
    for (final all in [false, true]) {
      for (final fromHistory in [false, true]) {
        test(
          '${all ? "retryAllFailed" : "retry"} checks ${fromHistory ? "history" : "index"} for ${native ? "native" : "Dart"}',
          () async {
            const track = Track(
              id: 'qobuz:retry',
              name: 'Retry',
              artists: 'Artist',
              isrc: 'RETRY',
            );
            final file = await File(
              '${dir.path}/retry.flac',
            ).writeAsString('audio');
            final worker = Worker(file.path)
              ..withPath = true
              ..error = 'network error';
            bridge.result = {'success': false, 'error': 'network error'};
            container = setup(worker: native ? worker : null);
            final queue = container.read(downloadQueueProvider.notifier);
            await queue.enqueue(track);
            await waitFor(
              () =>
                  container.read(downloadQueueProvider).single.status ==
                  'failed',
            );
            if (fromHistory) {
              await db.upsert(
                HistoryEntry(
                  id: 'existing',
                  track: track,
                  service: 'qobuz',
                  filePath: file.path,
                  downloadedAt: DateTime.now(),
                ),
              );
            } else {
              bridge.indexedPath = file.path;
            }
            if (all) {
              queue.retryAllFailed();
            } else {
              queue.retry(container.read(downloadQueueProvider).single.itemId);
            }
            await waitFor(
              () => [
                'done',
                'failed',
              ].contains(container.read(downloadQueueProvider).single.status),
            );
            expect(
              container.read(downloadQueueProvider).single.alreadyInLibrary,
              isTrue,
            );
            expect(native ? worker.starts : bridge.downloads, 1);
          },
        );
      }
    }
    test(
      'downloadAnyway bypasses history and index for ${native ? "native" : "Dart"}',
      () async {
        const track = Track(
          id: 'qobuz:42',
          source: 'qobuz',
          name: 'Song',
          artists: 'Artist',
          isrc: 'SAME',
        );
        final file = await File(
          '${dir.path}/existing.flac',
        ).writeAsString('audio');
        await db.upsert(
          HistoryEntry(
            id: 'existing',
            track: track,
            service: 'qobuz',
            filePath: file.path,
            downloadedAt: DateTime.now(),
          ),
        );
        bridge.indexedPath = file.path;
        bridge.result = {'success': true, 'file_path': file.path};
        final worker = Worker(file.path)..withPath = true;
        container = setup(worker: native ? worker : null);
        final queue = container.read(downloadQueueProvider.notifier);
        await queue.enqueue(track, service: 'qobuz', quality: 'FLAC');
        await waitFor(() => container.read(downloadQueueProvider).single.status == 'done');
        expect(
          container.read(downloadQueueProvider).single.alreadyInLibrary,
          isTrue,
        );
        queue.downloadAnyway(container.read(downloadQueueProvider).single.itemId);
        await waitFor(() => (native ? worker.starts : bridge.downloads) == 1);
        expect(native ? worker.starts : bridge.downloads, 1);
        if (native) {
          expect(worker.lastRequest?['bypass_duplicate_check'], isTrue);
        }
        expect(container.read(downloadQueueProvider).single.service, 'qobuz');
        expect(container.read(downloadQueueProvider).single.quality, 'FLAC');
      },
    );
  }
  test('native duplicate batch refreshes the watched library once', () async {
    final file = await File('${dir.path}/indexed.flac').writeAsString('audio');
    bridge.indexedPath = file.path;
    container = setup(worker: Worker(file.path)..withPath = true);
    final subscription = container.listen(libraryProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(libraryProvider.future);
    bridge.scans = 0;
    final queue = container.read(downloadQueueProvider.notifier);
    await queue.pause();
    for (var i = 0; i < 5; i++) {
      await queue.enqueue(
        Track(
          id: 'qobuz:$i',
          name: 'Song $i',
          artists: 'Artist',
          isrc: 'ISRC$i',
        ),
      );
    }
    await queue.resume();
    await waitFor(
      () => container
          .read(downloadQueueProvider)
          .every((e) => e.status == 'done'),
    );
    await settle();
    expect(bridge.scans, 1);
  });
  for (final native in [false, true]) {
    test(
      'history precheck prevents ${native ? 'native' : 'Dart'} work, missing file permits download',
      () async {
        final file = await File(
          '${dir.path}/existing.flac',
        ).writeAsString('audio');
        await db.upsert(
          HistoryEntry(
            id: 'existing',
            track: song,
            service: 'qobuz',
            filePath: file.path,
            downloadedAt: DateTime.now(),
          ),
        );
        final worker = Worker(file.path)..withPath = true;
        bridge.result = {'success': true, 'file_path': file.path};
        container = setup(worker: native ? worker : null);
        final queue = container.read(downloadQueueProvider.notifier);
        await queue.enqueue(song);
        await waitFor(() => container.read(downloadQueueProvider).single.status == 'done');
        expect(bridge.downloads, 0);
        expect(worker.starts, 0);
        expect(
          container.read(downloadQueueProvider).single.alreadyInLibrary,
          isTrue,
        );
        queue.clearCompleted();
        expect(container.read(downloadQueueProvider), isEmpty);
        await file.delete();
        await queue.enqueue(song);
        await waitFor(() => (native ? worker.starts : bridge.downloads) == 1);
        expect(native ? worker.starts : bridge.downloads, 1);
      },
    );
  }
}
