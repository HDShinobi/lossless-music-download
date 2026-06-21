import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'app_locale';
  @override
  Locale build() => const Locale('vi'); // default Vietnamese

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final code = p.getString(_key);
    if (code != null) state = Locale(code);
  }

  Future<void> set(Locale l) async {
    state = l;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, l.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
