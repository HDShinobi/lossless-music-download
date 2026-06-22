import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Controllable fake BackendBridge
// ---------------------------------------------------------------------------

class _FakeBridge extends BackendBridge {
  /// The result that downloadByStrategy will return.
  Map<String, dynamic> downloadResult = {};

  /// Whether downloadByStrategy should throw.
  bool throwOnDownload = false;

  final List<String> cancelCalls = [];
  final List<DownloadRequest> downloadCalls = [];

  @override
  Future<void> setDownloadDirectory(String path) async {}

  @override
  Future<void> allowDownloadDir(String path) async {}

  @override
  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) async {
    downloadCalls.add(req);
    if (throwOnDownload) throw Exception('download error');
    return downloadResult;
  }

  @override
  Future<List<DownloadProgress>> getAllProgress() async => [];

  @override
  Future<void> cancelDownload(String itemId) async {
    cancelCalls.add(itemId);
  }
}

// ---------------------------------------------------------------------------
// Helper — build a ProviderContainer with overrides
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeBridge bridge) {
  final container = ProviderContainer(
    overrides: [
      backendBridgeProvider.overrideWithValue(bridge),
      downloadDirPathProvider.overrideWithValue(
        Future.value('/fake/downloads'),
      ),
    ],
  );
  // The notifier references downloadsProvider inside build(); that provider
  // will call backendBridgeProvider.getAllProgress() which returns [].
  return container;
}

// ---------------------------------------------------------------------------
// Test track fixture
// ---------------------------------------------------------------------------

const _track = Track(
  id: 'test-track-id',
  name: 'Test Song',
  artists: 'Test Artist',
  albumName: 'Test Album',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DownloadQueueController', () {
    // (a) enqueue immediately adds entry; success map → 'done'
    test('enqueue adds entry instantly with status downloading, then done on success',
        () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      // Read the notifier to initialise it.
      final notifier = container.read(downloadQueueProvider.notifier);

      // Snapshot state *right after* enqueue is called (before await resolves).
      // Because enqueue is async we check state after awaiting.
      final future = notifier.enqueue(_track);

      // State should already have 1 entry (prepended before the await).
      final immediateState = container.read(downloadQueueProvider);
      expect(immediateState, hasLength(1));
      expect(immediateState.first.track, equals(_track));
      expect(immediateState.first.status, equals('downloading'));

      await future;

      final finalState = container.read(downloadQueueProvider);
      expect(finalState, hasLength(1));
      expect(finalState.first.status, equals('done'));
      expect(finalState.first.progress, equals(1.0));
    });

    // (b) success: false → 'failed'
    test('enqueue → failed when downloadByStrategy returns success=false',
        () async {
      final bridge = _FakeBridge()..downloadResult = {'success': false};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(downloadQueueProvider.notifier).enqueue(_track);

      final state = container.read(downloadQueueProvider);
      expect(state.first.status, equals('failed'));
    });

    // (b) error field set → 'failed'
    test('enqueue → failed when downloadByStrategy returns error field',
        () async {
      final bridge = _FakeBridge()
        ..downloadResult = {'error': 'something went wrong'};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(downloadQueueProvider.notifier).enqueue(_track);

      final state = container.read(downloadQueueProvider);
      expect(state.first.status, equals('failed'));
    });

    // (c) throwing → 'failed'
    test('enqueue → failed when downloadByStrategy throws', () async {
      final bridge = _FakeBridge()..throwOnDownload = true;
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(downloadQueueProvider.notifier).enqueue(_track);

      final state = container.read(downloadQueueProvider);
      expect(state.first.status, equals('failed'));
    });

    // (d) remove → entry gone + cancelDownload called
    test('remove removes the entry and calls cancelDownload', () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      // Enqueue then capture itemId before awaiting (download completes fast).
      final future = notifier.enqueue(_track);
      final itemId =
          container.read(downloadQueueProvider).first.itemId;

      await future;

      // Now remove it.
      notifier.remove(itemId);

      expect(container.read(downloadQueueProvider), isEmpty);
      expect(bridge.cancelCalls, contains(itemId));
    });

    // enqueue builds a DownloadRequest with the correct fields
    test('enqueue passes correct DownloadRequest to bridge', () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      await container
          .read(downloadQueueProvider.notifier)
          .enqueue(_track, source: 'mysource', quality: 'lossless');

      expect(bridge.downloadCalls, hasLength(1));
      final req = bridge.downloadCalls.first;
      final json = req.toJson();
      expect(json['track_name'], 'Test Song');
      expect(json['artist_name'], 'Test Artist');
      expect(json['output_dir'], '/fake/downloads');
      expect(json['use_extensions'], isTrue);
      expect(json['source'], 'mysource');
      expect(json['quality'], 'lossless');
    });

    test('enqueue maps the track id to the right backend identifier', () async {
      // qobuz-prefixed id -> qobuz_id, no spotify_id
      final b1 = _FakeBridge()..downloadResult = {};
      final c1 = _makeContainer(b1);
      addTearDown(c1.dispose);
      await c1
          .read(downloadQueueProvider.notifier)
          .enqueue(const Track(id: 'qobuz:12345', name: 'S', artists: 'A'));
      final j1 = b1.downloadCalls.first.toJson();
      expect(j1['qobuz_id'], '12345');
      expect(j1.containsKey('spotify_id'), isFalse);

      // tidal-prefixed id -> tidal_id, no spotify_id
      final b2 = _FakeBridge()..downloadResult = {};
      final c2 = _makeContainer(b2);
      addTearDown(c2.dispose);
      await c2
          .read(downloadQueueProvider.notifier)
          .enqueue(const Track(id: 'tidal:999', name: 'S', artists: 'A'));
      final j2 = b2.downloadCalls.first.toJson();
      expect(j2['tidal_id'], '999');
      expect(j2.containsKey('spotify_id'), isFalse);

      // plain id -> spotify_id
      final b3 = _FakeBridge()..downloadResult = {};
      final c3 = _makeContainer(b3);
      addTearDown(c3.dispose);
      await c3
          .read(downloadQueueProvider.notifier)
          .enqueue(const Track(id: 'abc123', name: 'S', artists: 'A'));
      final j3 = b3.downloadCalls.first.toJson();
      expect(j3['spotify_id'], 'abc123');
      expect(j3.containsKey('qobuz_id'), isFalse);
    });

    // retry removes old entry and re-enqueues
    test('retry removes old entry and re-enqueues the track', () async {
      final bridge = _FakeBridge()
        ..downloadResult = {'success': false}; // first call fails
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      // First enqueue — ends in 'failed'.
      await notifier.enqueue(_track);
      final failedId = container.read(downloadQueueProvider).first.itemId;
      expect(container.read(downloadQueueProvider).first.status, 'failed');

      // Now make the bridge succeed for the retry.
      bridge.downloadResult = {};
      bridge.throwOnDownload = false;

      notifier.retry(failedId);
      // retry calls enqueue internally; wait for it to settle.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(downloadQueueProvider);
      // The failed entry should be gone; a new 'done' entry should exist.
      expect(state.where((e) => e.itemId == failedId), isEmpty);
      expect(state, hasLength(1));
      expect(state.first.status, equals('done'));
    });
  });
}
