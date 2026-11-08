import 'dart:io';
import 'dart:async';
import 'package:lossless_music_download/providers/library_busy_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import '../helpers/library_queue_fake.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_manager.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

class _FakeBridge extends BackendBridge {
  final List<({String path, Map<String, String> fields})> edits = [];
  Completer<void>? gate;
  Map<String, dynamic> editResult = {'success': true, 'method': 'native'};

  @override
  Future<Map<String, dynamic>> editFileMetadata(
    String filePath,
    Map<String, String> metadata,
  ) async {
    await gate?.future;
    edits.add((path: filePath, fields: metadata));
    return editResult;
  }
}

void main() {
  test(
    'edit and delete hold the shared running state for their duration',
    () async {
      final fake = _FakeBridge()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(fake),
          downloadQueueProvider.overrideWith(LibraryQueueFake.new),
        ],
      );
      addTearDown(container.dispose);
      final manager = container.read(libraryManagerProvider.notifier);
      final editing = manager.editMetadata('/song.flac', {'title': 'New'});
      expect(container.read(libraryBusyProvider), isTrue);
      expect(
        container.read(libraryReorganizeRunningProvider.notifier).tryStart(),
        isFalse,
      );
      fake.gate!.complete();
      await editing;
      expect(container.read(libraryBusyProvider), isFalse);
      final deleting = manager.delete('/missing.flac');
      expect(container.read(libraryBusyProvider), isTrue);
      await deleting;
      expect(container.read(libraryBusyProvider), isFalse);
    },
  );
  group('buildEditFields', () {
    test('maps non-empty form values to lowercase backend keys', () {
      final f = buildEditFields(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        albumArtist: 'AArtist',
        year: '2024',
        genre: 'Pop',
        trackNumber: '3',
      );
      expect(f, {
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
        'album_artist': 'AArtist',
        'date': '2024',
        'genre': 'Pop',
        'track_number': '3',
      });
    });

    test('omits empty/whitespace-only fields', () {
      final f = buildEditFields(title: 'Song', artist: '', album: '   ');
      expect(f.keys, ['title']);
      expect(f['title'], 'Song');
    });

    test('trims surrounding whitespace', () {
      final f = buildEditFields(title: '  Song  ');
      expect(f['title'], 'Song');
    });
  });

  group('LibraryManager.delete', () {
    test('removes the file from disk', () async {
      final tmp = await Directory.systemTemp.createTemp('libmgr');
      final file = File('${tmp.path}/song.flac');
      await file.writeAsString('x');
      expect(file.existsSync(), isTrue);

      final container = ProviderContainer(
        overrides: [downloadQueueProvider.overrideWith(LibraryQueueFake.new)],
      );
      addTearDown(container.dispose);

      await container.read(libraryManagerProvider.notifier).delete(file.path);

      expect(file.existsSync(), isFalse);
      await tmp.delete(recursive: true);
    });

    test('does not throw when the file is already gone', () async {
      final container = ProviderContainer(
        overrides: [downloadQueueProvider.overrideWith(LibraryQueueFake.new)],
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(libraryManagerProvider.notifier)
            .delete('/no/such/file.flac'),
        completes,
      );
    });
  });

  group('LibraryManager.editMetadata', () {
    test('forwards the built fields to the backend bridge', () async {
      final fake = _FakeBridge();
      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(fake),
          downloadQueueProvider.overrideWith(LibraryQueueFake.new),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryManagerProvider.notifier).editMetadata(
        '/music/song.flac',
        {'title': 'New Title', 'artist': 'New Artist'},
      );

      expect(fake.edits, hasLength(1));
      expect(fake.edits.single.path, '/music/song.flac');
      expect(fake.edits.single.fields['title'], 'New Title');
    });
  });
}
