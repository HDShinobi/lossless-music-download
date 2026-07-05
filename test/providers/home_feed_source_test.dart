import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/home_feed_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default is null (auto)', () {
    final c = ProviderContainer(); addTearDown(c.dispose);
    expect(c.read(homeFeedSourceProvider), isNull);
  });

  test('set persists a specific id', () async {
    final c = ProviderContainer(); addTearDown(c.dispose);
    await c.read(homeFeedSourceProvider.notifier).set('ytmusic');
    expect(c.read(homeFeedSourceProvider), 'ytmusic');
    expect((await SharedPreferences.getInstance()).getString('home_feed_source'), 'ytmusic');
  });

  test('set(null) clears the key', () async {
    SharedPreferences.setMockInitialValues({'home_feed_source': 'ytmusic'});
    final c = ProviderContainer(); addTearDown(c.dispose);
    await c.read(homeFeedSourceProvider.notifier).set(null);
    expect(c.read(homeFeedSourceProvider), isNull);
    expect((await SharedPreferences.getInstance()).getString('home_feed_source'), isNull);
  });
}
