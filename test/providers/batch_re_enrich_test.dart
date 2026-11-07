import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/models/library_entry.dart';
import 'package:lossless_music_download/providers/batch_re_enrich_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import '../helpers/re_enrich_fakes.dart';
import '../helpers/library_queue_fake.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/library_busy_provider.dart';

LibraryEntry entry(int n) => LibraryEntry(
  path: '/$n.flac',
  name: '$n.flac',
  title: 'Song $n',
  artistName: 'A',
  albumName: 'Album',
  sizeBytes: 0,
  format: 'FLAC',
  verified: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBridge bridge;
  late FakeHistory history;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'embed_cover': false,
      'embed_lyrics': false,
      'artist_tag_mode': 'joined',
      'metadata_separators': '{"artist":" / "}',
    });
    bridge = FakeBridge();
    history = FakeHistory();
    container = ProviderContainer(
      overrides: [
        downloadQueueProvider.overrideWith(LibraryQueueFake.new),
        downloadDirProvider.overrideWith((_) async => '/downloads'),
        backendBridgeProvider.overrideWithValue(bridge),
        historyDatabaseProvider.overrideWith((_) async => history),
      ],
    );
  });
  tearDown(() => container.dispose());
  test(
    'reorganize claims the library and blocks batch and another reorganize',
    () async {
      final reorganize = container.read(
        libraryReorganizeRunningProvider.notifier,
      );
      expect(reorganize.tryStart(), isTrue);
      expect(container.read(libraryBusyProvider), isTrue);
      expect(reorganize.tryStart(), isFalse);
      await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
      expect(bridge.requests, isEmpty);
      reorganize.finish();
      expect(container.read(libraryBusyProvider), isFalse);
      await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
      expect(history.paths, ['/1.flac']);
    },
  );
  test(
    'batch claims the library before awaiting settings and blocks reorganize',
    () async {
      bridge.gate = Completer<void>();
      final job = container.read(batchReEnrichProvider.notifier).start([
        entry(1),
      ]);
      expect(
        container.read(libraryReorganizeRunningProvider.notifier).tryStart(),
        isFalse,
      );
      bridge.gate!.complete();
      await job;
      expect(
        container.read(libraryReorganizeRunningProvider.notifier).tryStart(),
        isTrue,
      );
    },
  );
  for (final useTarget in [false, true]) {
    test(
      'queue arriving during a batch drops ${useTarget ? 'target' : 'filePath'} match',
      () async {
        SharedPreferences.setMockInitialValues({
          'filename_template': '{title}',
        });
        bridge.writeGate = Completer<void>();
        final path = useTarget ? '/downloads/A/Album/Song.flac' : '/2.flac';
        final second = LibraryEntry(
          path: path,
          name: 'Song.flac',
          sizeBytes: 0,
          format: 'FLAC',
          verified: true,
        );
        final job = container.read(batchReEnrichProvider.notifier).start([
          entry(1),
          second,
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(bridge.requests, hasLength(2)); // first file is in its write
        (container.read(downloadQueueProvider.notifier) as LibraryQueueFake)
            .replace([
              queueEntry(
                'processing',
                filePath: useTarget ? null : '/folder/../2.flac',
              ),
            ]);
        bridge.writeGate!.complete();
        await job;
        expect(
          bridge.requests.every((r) => r['file_path'] == '/1.flac'),
          isTrue,
        );
        expect(history.paths, ['/1.flac']);
        expect(container.read(batchReEnrichProvider).completed, 1);
      },
    );
  }
  for (final status in [
    'queued',
    'downloading',
    'processing',
    'paused',
    'waiting_wifi',
  ]) {
    test('start does nothing while queue status is $status', () async {
      (container.read(downloadQueueProvider.notifier) as LibraryQueueFake)
          .replace([queueEntry(status, filePath: '/1.flac')]);
      await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
      expect(bridge.requests, isEmpty);
      expect(container.read(batchReEnrichProvider).total, 0);
      expect(history.paths, isEmpty);
    });
  }
  test('done and failed entries allow a batch', () async {
    (container.read(downloadQueueProvider.notifier) as LibraryQueueFake)
        .replace([queueEntry('done'), queueEntry('failed')]);
    await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
    expect(container.read(batchReEnrichProvider).completed, 1);
    expect(history.paths, ['/1.flac']);
  });
  test(
    'sequential progress, settings, and errors retain successful history',
    () async {
      bridge.gate = Completer<void>();
      final runner = container.read(batchReEnrichProvider.notifier);
      final job = runner.start([entry(1), entry(2), entry(3), entry(1)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bridge.requests, hasLength(1));
      var state = container.read(batchReEnrichProvider);
      expect(state.running, isTrue);
      expect(state.total, 3);
      expect(state.currentTitle, 'Song 1');
      expect(state.completed, 0);
      bridge.gate!.complete();
      await job;
      state = container.read(batchReEnrichProvider);
      expect(state.running, isFalse);
      expect(state.completed, 3);
      expect(state.failures.map((e) => e.path), ['/2.flac', '/3.flac']);
      expect(history.paths, ['/1.flac']);
      final write = bridge.requests[1];
      expect(write['artist_name'], 'A / B');
      expect(write['artist_tag_mode'], 'joined');
      expect(write['embed_lyrics'], false);
      expect(write['update_fields'], isNot(contains('cover')));
      expect(write['update_fields'], isNot(contains('lyrics')));
      expect(bridge.requests.first['search_online'], true);
    },
  );
  test(
    'failed separator finishing step still updates history for written file',
    () async {
      SharedPreferences.setMockInitialValues({
        'artist_tag_mode': 'split_vorbis',
        'metadata_separators': '{"artist":"; "}',
      });
      bridge.editError = StateError('finishing failed');
      await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
      final state = container.read(batchReEnrichProvider);
      expect(history.paths, ['/1.flac']);
      expect(state.completed, 1);
      expect(state.failures.single.error, contains('finishing failed'));
    },
  );
  test('sidecar-only lyrics fetches without embedding lyrics', () async {
    SharedPreferences.setMockInitialValues({
      'embed_lyrics': false,
      'write_lrc_sidecar': true,
    });
    await container.read(batchReEnrichProvider.notifier).start([entry(1)]);
    final write = bridge.requests.last;
    expect(write['lyrics_mode'], 'external');
    expect(write['embed_lyrics'], true); // Rust flag means fetch lyrics.
    expect(write['update_fields'], contains('lyrics'));
  });
  test(
    'cancel during a write finishes that file and dispatches no next item',
    () async {
      bridge.writeGate = Completer<void>();
      final runner = container.read(batchReEnrichProvider.notifier);
      final job = runner.start([entry(1), entry(2)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      runner.cancel();
      await runner.start([entry(3)]); // never overlap an active batch
      bridge.writeGate!.complete();
      await job;
      final state = container.read(batchReEnrichProvider);
      expect(state.cancelled, true);
      expect(state.running, false);
      expect(bridge.requests.every((r) => r['file_path'] == '/1.flac'), true);
      expect(state.completed, 1);
    },
  );
}
