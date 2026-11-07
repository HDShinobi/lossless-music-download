import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/models/lyrics_settings.dart';
import 'package:lossless_music_download/providers/lyrics_settings_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.losslessmusic/native');
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('untouched startup keeps engine defaults as empty JSON', () async {
    await BackendBridge().initExtensionSystem('/ext', '/data');
    expect(calls.single.arguments, {
      'extDir': '/ext',
      'dataDir': '/data',
      'providers_json': '[]',
      'options_json': '{}',
    });
    expect(const LyricsSettings().effectiveProviders, [
      'apple_music',
      'lrcred',
      'mornye_lyrics',
      'lyricsplus',
      'lrclib',
    ]);
  });

  test(
    'saved provider order and options reach startup and survive restart',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(lyricsSettingsProvider.future);
      await container.read(lyricsSettingsProvider.notifier).setProviders([
        'netease',
        'lrclib',
      ]);
      await container
          .read(lyricsSettingsProvider.notifier)
          .setOption('include_translation_netease', true);
      expect(calls.map((e) => e.method), [
        'setLyricsProviders',
        'setLyricsFetchOptions',
      ]);
      expect(jsonDecode((calls.last.arguments as Map)['options_json']), {
        'include_translation_netease': true,
      });
      calls.clear();
      await BackendBridge().initExtensionSystem('/ext', '/data');
      expect(jsonDecode((calls.single.arguments as Map)['providers_json']), [
        'netease',
        'lrclib',
      ]);
      expect(jsonDecode((calls.single.arguments as Map)['options_json']), {
        'include_translation_netease': true,
      });
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      expect(
        (await fresh.read(lyricsSettingsProvider.future)).effectiveProviders,
        ['netease', 'lrclib'],
      );
    },
  );

  test('empty selection resets defaults and language is normalized', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(lyricsSettingsProvider.future);
    await container.read(lyricsSettingsProvider.notifier).setProviders([]);
    await container
        .read(lyricsSettingsProvider.notifier)
        .setOption('musixmatch_language', ' VI ! ');
    expect(
      (await container.read(
        lyricsSettingsProvider.future,
      )).options['musixmatch_language'],
      'vi',
    );
    expect(
      (await container.read(
        lyricsSettingsProvider.future,
      )).effectiveProviders.length,
      5,
    );
  });
  test(
    'corrupt preferences fall back to the unchanged engine defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'lyrics_providers': '{',
        'lyrics_fetch_options': '[',
      });
      final settings = await LyricsSettings.load();
      expect(settings.providersJson, '[]');
      expect(settings.optionsJson, '{}');
    },
  );

  test(
    'runtime rejection keeps the previous persisted provider order',
    () async {
      SharedPreferences.setMockInitialValues({
        'lyrics_providers': '["lrclib"]',
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'BACKEND_ERROR'),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(lyricsSettingsProvider.future);
      await expectLater(
        container.read(lyricsSettingsProvider.notifier).setProviders([
          'netease',
        ]),
        throwsA(isA<PlatformException>()),
      );
      expect(container.read(lyricsSettingsProvider).value!.providers, [
        'lrclib',
      ]);
      expect(
        (await SharedPreferences.getInstance()).getString('lyrics_providers'),
        '["lrclib"]',
      );
    },
  );
}
