import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/utils/extension_verification_coordinator.dart';

const _track = Track(id: 'trk-1', name: 'Song', artists: 'Artist');

DownloadEntry _entry({
  String itemId = 'dl_1',
  String status = 'failed',
  String? service = 'amazon',
  String? verificationService,
  String? error = 'Download failed: VERIFY_REQUIRED at signedJSON',
  Track track = _track,
}) {
  return DownloadEntry(
    track: track,
    itemId: itemId,
    status: status,
    progress: 0,
    bytesReceived: 0,
    service: service,
    error: error,
    verificationService: verificationService,
  );
}

class _Recorder {
  final opened = <String>[];
  final retried = <String>[];
  bool openResult = true;

  late final ExtensionVerificationCoordinator coordinator =
      ExtensionVerificationCoordinator(
    openVerification: (id) async {
      opened.add(id);
      return openResult;
    },
    retryItem: retried.add,
  );
}

void main() {
  group('ExtensionVerificationCoordinator', () {
    test('opens verification for the backend-reported extension, '
        'not the user-chosen source', () async {
      final r = _Recorder();
      r.coordinator.onQueueChanged(
        const [],
        [_entry(service: 'amazon', verificationService: 'qobuz-web')],
      );
      await Future<void>.delayed(Duration.zero);
      expect(r.opened, ['qobuz-web']);
    });

    test('falls back to the entry service when backend reported none',
        () async {
      final r = _Recorder();
      r.coordinator.onQueueChanged(const [], [_entry(service: 'deezer')]);
      await Future<void>.delayed(Duration.zero);
      expect(r.opened, ['deezer']);
    });

    test('ignores failures that are not verification errors', () async {
      final r = _Recorder();
      r.coordinator.onQueueChanged(
        const [],
        [_entry(error: 'network error')],
      );
      await Future<void>.delayed(Duration.zero);
      expect(r.opened, isEmpty);
    });

    test('does not reopen while a challenge for the same extension is pending',
        () async {
      final r = _Recorder();
      final first = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged(const [], [first]);
      await Future<void>.delayed(Duration.zero);

      final second = _entry(itemId: 'dl_2', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged([first], [second, first]);
      await Future<void>.delayed(Duration.zero);

      expect(r.opened, ['qobuz-web']);
    });

    test('an abandoned challenge stops blocking after the timeout', () {
      fakeAsync((async) {
        final r = _Recorder();
        final first = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
        r.coordinator.onQueueChanged(const [], [first]);
        async.flushMicrotasks();
        expect(r.opened, ['qobuz-web']);

        // No grant event ever arrives (user closed the browser).
        async.elapse(const Duration(minutes: 5, seconds: 1));

        final second = _entry(itemId: 'dl_2', verificationService: 'qobuz-web');
        r.coordinator.onQueueChanged([first], [second, first]);
        async.flushMicrotasks();
        expect(r.opened, ['qobuz-web', 'qobuz-web']);
      });
    });

    test('clears the pending flag when the browser could not be opened',
        () async {
      final r = _Recorder()..openResult = false;
      final first = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged(const [], [first]);
      await Future<void>.delayed(Duration.zero);

      r.openResult = true;
      final second = _entry(itemId: 'dl_2', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged([first], [second, first]);
      await Future<void>.delayed(Duration.zero);

      expect(r.opened, ['qobuz-web', 'qobuz-web']);
    });

    test('successful grant auto-retries the failed entries for that extension',
        () async {
      final r = _Recorder();
      final failed = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged(const [], [failed]);
      await Future<void>.delayed(Duration.zero);

      r.coordinator.onGrantCompleted('qobuz-web', true, [failed]);
      expect(r.retried, ['dl_1']);
    });

    test('failed grant does not retry but unblocks the extension', () async {
      final r = _Recorder();
      final failed = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged(const [], [failed]);
      await Future<void>.delayed(Duration.zero);

      r.coordinator.onGrantCompleted('qobuz-web', false, [failed]);
      expect(r.retried, isEmpty);

      // A later failure may open the challenge again.
      final second = _entry(itemId: 'dl_2', verificationService: 'qobuz-web');
      r.coordinator.onQueueChanged([failed], [second, failed]);
      await Future<void>.delayed(Duration.zero);
      expect(r.opened, ['qobuz-web', 'qobuz-web']);
    });

    test('grant does not retry entries that failed for another extension',
        () async {
      final r = _Recorder();
      final failed = _entry(itemId: 'dl_1', verificationService: 'tidal-web');
      r.coordinator.onGrantCompleted('qobuz-web', true, [failed]);
      expect(r.retried, isEmpty);
    });

    test('auto-retries a given track+extension only once per session '
        '(no endless verify loop)', () async {
      final r = _Recorder();
      final failed1 = _entry(itemId: 'dl_1', verificationService: 'qobuz-web');
      r.coordinator.onGrantCompleted('qobuz-web', true, [failed1]);
      expect(r.retried, ['dl_1']);

      // Retry produced a new item that failed with VERIFY again; a second
      // grant must not loop forever on the same track.
      final failed2 = _entry(itemId: 'dl_2', verificationService: 'qobuz-web');
      r.coordinator.onGrantCompleted('qobuz-web', true, [failed2]);
      expect(r.retried, ['dl_1']);
    });
  });
}
