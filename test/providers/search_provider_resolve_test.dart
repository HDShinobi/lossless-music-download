import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/search_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:mocktail/mocktail.dart';

class FakeBackendBridge extends Fake implements BackendBridge {
  final Map<String, dynamic>? Function(String url) handler;
  FakeBackendBridge(this.handler);

  @override
  Future<Map<String, dynamic>?> handleUrl(String url) async =>
      handler(url);
}

void main() {
  group('SearchNotifier.resolveFromUrl', () {
    ProviderContainer makeContainer(FakeBackendBridge bridge) =>
        ProviderContainer(overrides: [
          backendBridgeProvider.overrideWithValue(bridge),
        ]);

    test('type:track -> 1 track with mapped name', () async {
      final bridge = FakeBackendBridge((_) => {
            'type': 'track',
            'track': {
              'id': 'abc',
              'name': 'Test Song',
              'artists': 'Artist A',
              'album_name': 'Album X',
              'images': 'https://cover.example.com/img.jpg',
              'duration_ms': 210000,
            },
          });
      final container = makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(searchProvider.notifier).resolveFromUrl(
            'https://open.spotify.com/track/abc',
          );

      final state = container.read(searchProvider);
      expect(state.hasValue, isTrue);
      final tracks = state.value!;
      expect(tracks.length, 1);
      expect(tracks.first.name, 'Test Song');
      expect(tracks.first.coverUrl, 'https://cover.example.com/img.jpg');
    });

    test('type:album -> 2 tracks', () async {
      final bridge = FakeBackendBridge((_) => {
            'type': 'album',
            'tracks': [
              {
                'id': 't1',
                'name': 'Track One',
                'artists': 'Artist B',
                'duration_ms': 180000,
              },
              {
                'id': 't2',
                'name': 'Track Two',
                'artists': 'Artist B',
                'duration_ms': 200000,
              },
            ],
          });
      final container = makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(searchProvider.notifier).resolveFromUrl(
            'https://open.spotify.com/album/xyz',
          );

      final state = container.read(searchProvider);
      expect(state.hasValue, isTrue);
      expect(state.value!.length, 2);
      expect(state.value!.map((t) => t.name).toList(),
          containsAll(['Track One', 'Track Two']));
    });

    test('null result -> empty list (no crash)', () async {
      final bridge = FakeBackendBridge((_) => null);
      final container = makeContainer(bridge);
      addTearDown(container.dispose);

      await container.read(searchProvider.notifier).resolveFromUrl(
            'https://not-a-music-link.example.com',
          );

      final state = container.read(searchProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, isEmpty);
    });
  });
}
