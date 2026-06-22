import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_progress.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/util/queue_view.dart';

void main() {
  const track = Track(id: 'tid1', name: 'My Song', artists: 'Artist');

  group('computeQueueView', () {
    test('first poll: speed is null (no prev sample)', () {
      final item = const DownloadProgress(
        itemId: 'dl_1',
        status: 'downloading',
        progress: 0.1,
        bytesReceived: 100,
      );
      final result = computeQueueView(
        items: [item],
        labels: {'dl_1': track},
        prev: {},
        nowMs: 1000,
      );

      expect(result.views, hasLength(1));
      final view = result.views.first;
      expect(view.track, track);
      expect(view.speedBytesPerSec, isNull);
      expect(view.eta, isNull);
      // totalBytes: 100 / 0.1 = 1000
      expect(view.totalBytes, 1000);

      // next sample map should have the item
      expect(result.next.containsKey('dl_1'), isTrue);
      expect(result.next['dl_1']!.bytes, 100);
      expect(result.next['dl_1']!.atMs, 1000);
    });

    test('second poll: speed and eta are derived correctly', () {
      final prevSample = Sample(100, 1000);
      final item = const DownloadProgress(
        itemId: 'dl_1',
        status: 'downloading',
        progress: 0.3,
        bytesReceived: 1100,
      );
      final result = computeQueueView(
        items: [item],
        labels: {'dl_1': track},
        prev: {'dl_1': prevSample},
        nowMs: 2000,
      );

      expect(result.views, hasLength(1));
      final view = result.views.first;
      expect(view.track, track);

      // totalBytes: 1100 / 0.3 ≈ 3667
      expect(view.totalBytes, closeTo(3667, 1));

      // speed: (1100 - 100) / ((2000 - 1000) / 1000) = 1000 bytes/s
      expect(view.speedBytesPerSec, closeTo(1000.0, 0.01));

      // eta > 0
      expect(view.eta, isNotNull);
      expect(view.eta!.inSeconds, greaterThan(0));
    });

    test('zero-progress item: totalBytes is null, no NaN', () {
      final item = const DownloadProgress(
        itemId: 'dl_2',
        status: 'queued',
        progress: 0.0,
        bytesReceived: 0,
      );
      final result = computeQueueView(
        items: [item],
        labels: {},
        prev: {},
        nowMs: 1000,
      );

      expect(result.views, hasLength(1));
      final view = result.views.first;
      expect(view.track, isNull);
      expect(view.totalBytes, isNull);
      expect(view.speedBytesPerSec, isNull);
      expect(view.eta, isNull);
    });

    test('no bytes delta between polls: speed stays null', () {
      final prevSample = Sample(500, 1000);
      final item = const DownloadProgress(
        itemId: 'dl_3',
        status: 'downloading',
        progress: 0.2,
        bytesReceived: 500,
      );
      final result = computeQueueView(
        items: [item],
        labels: {'dl_3': track},
        prev: {'dl_3': prevSample},
        nowMs: 2000,
      );

      final view = result.views.first;
      // bytesDelta = 0, speed stays null
      expect(view.speedBytesPerSec, isNull);
    });
  });
}
