import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
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

  @override
  bool get isAvailable => true;

  @override
  Future<void> start(List<Map<String, dynamic>> requests, {required String runId}) async {
    startedBatches.add(requests);
    snapshotToReturn = NativeWorkerSnapshot(
      runId: runId,
      isRunning: false,
      items: requests
          .map((r) => NativeWorkerItemState(
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

    await container.read(downloadQueueProvider.notifier).enqueue(_track);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(nativeWorker.startedBatches, hasLength(1));
    final request = nativeWorker.startedBatches.first.single;
    expect(request['track_name'], 'Native Song');
    expect(request['artist_name'], 'Native Artist');

    final state = container.read(downloadQueueProvider);
    expect(state.first.status, 'done');
    expect(state.first.progress, 1.0);
  });
}
