import 'dart:async';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/history_database.dart';

class FakeBridge extends BackendBridge {
  final requests = <Map<String, dynamic>>[];
  Object? editError;
  @override
  Future<Map<String, dynamic>> editFileMetadata(
    String path,
    Map<String, String> fields,
  ) async {
    if (editError != null) throw editError!;
    return {'method': 'native', 'success': true};
  }

  Completer<void>? gate;
  Completer<void>? writeGate;
  @override
  Future<Map<String, dynamic>> reEnrichFile(
    Map<String, dynamic> request,
  ) async {
    requests.add(request);
    if (request['preview_only'] == true) {
      await gate?.future;
      if (request['file_path'] == '/2.flac') throw StateError('lookup failed');
      return {
        'method': 'preview',
        'success': true,
        'enriched_metadata': {
          'track_name': 'Updated',
          'artist_name': 'A, B',
          'album_name': 'Album',
        },
      };
    }
    await writeGate?.future;
    if (request['file_path'] == '/3.flac') {
      return {'success': false, 'error': 'write failed'};
    }
    return {
      'method': 'native',
      'success': true,
      'enriched_metadata': {
        'track_name': 'Updated',
        'artist_name': request['artist_name'],
      },
    };
  }
}

class FakeHistory extends HistoryDatabase {
  FakeHistory() : super(path: ':memory:');
  final paths = <String>[];
  @override
  Future<void> updateReEnriched(
    String path,
    Map<String, dynamic> result,
  ) async {
    paths.add(path);
  }
}
