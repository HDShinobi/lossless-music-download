import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('askBeforeDownloadProvider', () {
    test('default state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(askBeforeDownloadProvider), isFalse);
    });

    test('set(true) updates state to true', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(askBeforeDownloadProvider.notifier).set(true);

      expect(container.read(askBeforeDownloadProvider), isTrue);
    });

    test('set(true) persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(askBeforeDownloadProvider.notifier).set(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ask_before_download'), isTrue);
    });

    test('set(false) updates state to false', () async {
      SharedPreferences.setMockInitialValues({'ask_before_download': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(askBeforeDownloadProvider.notifier).set(false);

      expect(container.read(askBeforeDownloadProvider), isFalse);
    });

    test('load() reads persisted value from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'ask_before_download': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(askBeforeDownloadProvider.notifier).load();

      expect(container.read(askBeforeDownloadProvider), isTrue);
    });

    test('load() defaults to false when no prefs key exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(askBeforeDownloadProvider.notifier).load();

      expect(container.read(askBeforeDownloadProvider), isFalse);
    });
  });
}
