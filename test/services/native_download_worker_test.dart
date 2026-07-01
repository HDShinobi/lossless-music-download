import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/native_download_worker.dart';

void main() {
  group('buildNativeWorkerRequest', () {
    test('wraps item id, names, and request JSON', () {
      final result = buildNativeWorkerRequest(
        itemId: 'dl_123',
        trackName: 'Song',
        artistName: 'Artist',
        requestJson: {'track_name': 'Song', 'output_dir': '/x'},
      );
      expect(result['contract_version'], 1);
      expect(result['item_id'], 'dl_123');
      expect(result['track_name'], 'Song');
      expect(result['artist_name'], 'Artist');
      expect(result['request_json'], '{"track_name":"Song","output_dir":"/x"}');
    });
  });

  group('NativeWorkerItemState.fromJson', () {
    test('parses all fields', () {
      final state = NativeWorkerItemState.fromJson({
        'item_id': 'dl_1',
        'status': 'downloading',
        'progress': 0.5,
        'bytes_received': 100,
        'bytes_total': 200,
        'error': null,
      });
      expect(state.itemId, 'dl_1');
      expect(state.status, 'downloading');
      expect(state.progress, 0.5);
      expect(state.bytesReceived, 100);
      expect(state.bytesTotal, 200);
      expect(state.error, isNull);
    });

    test('defaults missing numeric fields to 0', () {
      final state = NativeWorkerItemState.fromJson({'item_id': 'dl_1', 'status': 'queued'});
      expect(state.progress, 0.0);
      expect(state.bytesReceived, 0);
      expect(state.bytesTotal, 0);
    });
  });

  group('NativeWorkerSnapshot.fromJson', () {
    test('parses run id, running flag, and items', () {
      final snapshot = NativeWorkerSnapshot.fromJson({
        'run_id': 'run_1',
        'is_running': true,
        'items': [
          {'item_id': 'dl_1', 'status': 'done', 'progress': 1.0, 'bytes_received': 10, 'bytes_total': 10},
        ],
      });
      expect(snapshot.runId, 'run_1');
      expect(snapshot.isRunning, isTrue);
      expect(snapshot.items, hasLength(1));
      expect(snapshot.items.first.itemId, 'dl_1');
    });

    test('defaults to not running with no items when fields missing', () {
      final snapshot = NativeWorkerSnapshot.fromJson({});
      expect(snapshot.runId, '');
      expect(snapshot.isRunning, isFalse);
      expect(snapshot.items, isEmpty);
    });
  });
}
