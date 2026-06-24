import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Controllable fake BackendBridge
// ---------------------------------------------------------------------------

class _FakeBridge extends BackendBridge {
  Map<String, dynamic> downloadResult = {};
  bool throwOnDownload = false;

  final List<String> cancelCalls = [];
  final List<DownloadRequest> downloadCalls = [];

  // Returns exists:true when duplicateIsrc is set and matches.
  String? duplicateIsrc;

  @override
  Future<Map<String, dynamic>> checkDuplicate(
      String outputDir, String isrc) async {
    if (duplicateIsrc != null && duplicateIsrc == isrc) {
      return {'exists': true, 'path': '/fake/existing.flac'};
    }
    return {'exists': false};
  }

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

  // Needed by _processQueue() priority-seed logic; return empty so the seed
  // branch is exercised without calling the MethodChannel in unit tests.
  @override
  Future<List<String>> getDownloadPriority() async => [];

  @override
  Future<void> setDownloadPriority(List<String> ids) async {}

  @override
  Stream<List<DownloadProgress>> progressStream() => Stream.value(const []);
}

// ---------------------------------------------------------------------------
// Helper — build a ProviderContainer with overrides
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeBridge bridge) {
  return ProviderContainer(
    overrides: [
      backendBridgeProvider.overrideWithValue(bridge),
      downloadDirPathProvider.overrideWithValue(
        Future.value('/fake/downloads'),
      ),
    ],
  );
}

/// Pump the Dart event loop enough times for _processQueue() to run to
/// completion (a few async hops: downloadDir, getDownloadPriority, bridge).
Future<void> _pump() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

// ---------------------------------------------------------------------------
// Test track fixture
// ---------------------------------------------------------------------------

const _track = Track(
  id: 'test-track-id',
  name: 'Test Song',
  artists: 'Test Artist',
  albumName: 'Test Album',
  isrc: 'USUM71400000',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DownloadQueueController', () {
    // (a) enqueue immediately adds visible entry; sequential processor sets done
    test(
        'enqueue adds entry instantly (status downloading), '
        'then done after processing', () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      // enqueue() has no internal awaits — returns immediately. But
      // _processQueue() starts synchronously and sets status→downloading
      // before its first internal await.
      final future = notifier.enqueue(_track);

      final immediateState = container.read(downloadQueueProvider);
      expect(immediateState, hasLength(1));
      expect(immediateState.first.track, equals(_track));
      expect(immediateState.first.status, equals('downloading'));

      // Wait for the sequential processor to finish.
      await future;
      await _pump();

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
      await _pump();

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
      await _pump();

      final state = container.read(downloadQueueProvider);
      expect(state.first.status, equals('failed'));
    });

    // (c) throwing → 'failed'
    test('enqueue → failed when downloadByStrategy throws', () async {
      final bridge = _FakeBridge()..throwOnDownload = true;
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(downloadQueueProvider.notifier).enqueue(_track);
      await _pump();

      final state = container.read(downloadQueueProvider);
      expect(state.first.status, equals('failed'));
    });

    // (d) remove → entry gone + cancelDownload called
    test('remove removes the entry and calls cancelDownload', () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      final future = notifier.enqueue(_track);
      final itemId = container.read(downloadQueueProvider).first.itemId;

      await future;
      await _pump();

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
          .enqueue(_track, service: 'mysource', quality: 'lossless');
      await _pump();

      expect(bridge.downloadCalls, hasLength(1));
      final req = bridge.downloadCalls.first;
      final json = req.toJson();
      expect(json['track_name'], 'Test Song');
      expect(json['artist_name'], 'Test Artist');
      expect(json['output_dir'], '/fake/downloads');
      expect(json['use_extensions'], isTrue);
      expect(json['use_fallback'], isTrue);
      expect(json['service'], 'mysource');
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
      await _pump();
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
      await _pump();
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
      await _pump();
      final j3 = b3.downloadCalls.first.toJson();
      expect(j3['spotify_id'], 'abc123');
      expect(j3.containsKey('qobuz_id'), isFalse);
    });

    // Sequential: second enqueue waits until first download completes
    test('second enqueue is processed after first completes', () async {
      final bridge = _FakeBridge()..downloadResult = {};
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      const track2 = Track(id: 'track-2', name: 'Song 2', artists: 'Artist B');
      unawaited(notifier.enqueue(_track));
      unawaited(notifier.enqueue(track2));

      // Allow both to complete sequentially.
      await _pump();
      await _pump();

      final state = container.read(downloadQueueProvider);
      expect(state, hasLength(2));
      expect(state.every((e) => e.status == 'done'), isTrue);
      // Both requests should have been sent to the bridge sequentially.
      expect(bridge.downloadCalls, hasLength(2));
    });

    // retry removes old entry and re-enqueues with original service/quality
    test('retry removes old entry and re-enqueues the track', () async {
      final bridge = _FakeBridge()
        ..downloadResult = {'success': false}; // first call fails
      final container = _makeContainer(bridge);
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);

      await notifier.enqueue(_track);
      await _pump();

      final failedId = container.read(downloadQueueProvider).first.itemId;
      expect(container.read(downloadQueueProvider).first.status, 'failed');

      // Now make the bridge succeed for the retry.
      bridge.downloadResult = {};
      bridge.throwOnDownload = false;

      notifier.retry(failedId);
      await _pump();

      final state = container.read(downloadQueueProvider);
      expect(state.where((e) => e.itemId == failedId), isEmpty);
      expect(state, hasLength(1));
      expect(state.first.status, equals('done'));
    });

    group('duplicate detection', () {
      test('marks item done without calling download when ISRC matches',
          () async {
        final bridge = _FakeBridge();
        bridge.duplicateIsrc = 'USUM71400101'; // matches trackWithIsrc.isrc
        final c = _makeContainer(bridge);
        addTearDown(c.dispose);

        const trackWithIsrc = Track(
          id: 'dup-track',
          name: 'Already Downloaded',
          artists: 'Artist',
          isrc: 'USUM71400101',
        );

        c.read(downloadQueueProvider.notifier).enqueue(trackWithIsrc);
        await _pump();
        await _pump();

        final entries = c.read(downloadQueueProvider);
        expect(entries.first.status, 'done');
        expect(bridge.downloadCalls, isEmpty);
      });

      test('proceeds with download when no ISRC', () async {
        final bridge = _FakeBridge();
        bridge.duplicateIsrc = 'USUM71400101';
        bridge.downloadResult = {'success': true};
        final c = _makeContainer(bridge);
        addTearDown(c.dispose);

        // Track without ISRC — cannot check duplicate, so download runs.
        const trackNoIsrc = Track(
          id: 'no-isrc-track',
          name: 'No ISRC Song',
          artists: 'Artist',
        );

        c.read(downloadQueueProvider.notifier).enqueue(trackNoIsrc);
        await _pump();
        await _pump();

        expect(bridge.downloadCalls, hasLength(1));
      });
    });
  });
}
