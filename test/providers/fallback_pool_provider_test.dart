import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/fallback_pool_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default state is null (means all)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(fallbackPoolProvider), isNull);
  });

  test('set explicit list persists as JSON', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(fallbackPoolProvider.notifier).set(['qobuz', 'tidal']);
    expect(c.read(fallbackPoolProvider), ['qobuz', 'tidal']);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('download_fallback_provider_ids')!),
        ['qobuz', 'tidal']);
  });

  test('set empty list coerces to null (all)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(fallbackPoolProvider.notifier).set(<String>[]);
    expect(c.read(fallbackPoolProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('download_fallback_provider_ids'), isNull);
  });
}
