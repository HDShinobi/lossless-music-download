import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/fallback_pool_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

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

  test('set pushes provider ids to the bridge (empty -> [] not sent)', () async {
    final pushed = <List<String>>[];
    final c = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(
        _FakeBridge(onSetFallback: (ids) => pushed.add(ids)),
      ),
    ]);
    addTearDown(c.dispose);
    await c.read(fallbackPoolProvider.notifier).set(['qobuz']);
    expect(pushed, [['qobuz']]);
  });

  test(
      'pushCurrent at startup does not block the persisted-value load '
      '(regression: pushCurrent must not set _explicitlySet)', () async {
    SharedPreferences.setMockInitialValues({
      'download_fallback_provider_ids': jsonEncode(['tidal']),
    });
    final pushed = <List<String>>[];
    final c = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(
        _FakeBridge(onSetFallback: (ids) => pushed.add(ids)),
      ),
    ]);
    addTearDown(c.dispose);
    // Simulate main.dart: first access of the notifier immediately followed
    // by pushCurrent(), before the async persisted-value load can resolve.
    await c.read(fallbackPoolProvider.notifier).pushCurrent();
    // Let build()'s persisted-load microtask settle.
    await Future.delayed(const Duration(milliseconds: 20));
    expect(c.read(fallbackPoolProvider), ['tidal']);
    expect(pushed.last, ['tidal']);
  });
}

class _FakeBridge extends BackendBridge {
  _FakeBridge({required this.onSetFallback});
  final void Function(List<String>) onSetFallback;
  @override
  Future<void> setDownloadFallbackProviderIds(List<String> ids) async =>
      onSetFallback(ids);
}
