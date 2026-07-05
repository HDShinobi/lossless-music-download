import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:lossless_music_download/services/backend_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.losslessmusic/native');
  final bridge = BackendBridge();
  final calls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getInstalledExtensions':
          return jsonEncode([
            {
              'id': 'deezer',
              'name': 'deezer',
              'display_name': 'Deezer',
              'version': '1.1.5',
              'enabled': true,
              'types': ['download_provider']
            }
          ]);
        case 'searchTracks':
          return jsonEncode({
            'tracks': [
              {'id': 't1', 'name': 'Song', 'artists': 'A'}
            ]
          });
        case 'getExtensionHomeFeed':
          return jsonEncode({'success': true, 'sections': []});
        default:
          return null;
      }
    });
  });
  tearDown(() => calls.clear());

  test('getInstalledExtensions parses list', () async {
    final list = await bridge.getInstalledExtensions();
    expect(list.single.id, 'deezer');
    expect(list.single.enabled, true);
  });

  test('searchTracks sends args + parses tracks', () async {
    final tracks = await bridge.searchTracks('hello', limit: 5);
    expect(tracks.single.name, 'Song');
    final c = calls.firstWhere((c) => c.method == 'searchTracks');
    expect(c.arguments['query'], 'hello');
    expect(c.arguments['limit'], 5);
  });

  test('setDownloadFallbackProviderIds sends JSON-encoded ids', () async {
    await bridge.setDownloadFallbackProviderIds(['qobuz', 'tidal']);
    final c = calls.firstWhere((c) => c.method == 'setDownloadFallbackProviderIds');
    expect(jsonDecode(c.arguments['idsJson']), ['qobuz', 'tidal']);
  });

  test('getExtensionHomeFeed sends id + decodes envelope', () async {
    final res = await bridge.getExtensionHomeFeed('ytmusic-spotiflac');
    expect(res, isNotNull);
    expect(res!['success'], true);
    final c = calls.firstWhere((c) => c.method == 'getExtensionHomeFeed');
    expect(c.arguments['extensionId'], 'ytmusic-spotiflac');
  });
}
