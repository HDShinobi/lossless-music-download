import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('load() restores persisted locale', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(localeProvider.notifier).load();
    expect(c.read(localeProvider), const Locale('en'));
  });
  test('default locale is vi when nothing saved', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(localeProvider.notifier).load();
    expect(c.read(localeProvider), const Locale('vi'));
  });
}
