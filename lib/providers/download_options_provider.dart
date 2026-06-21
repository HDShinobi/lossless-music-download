import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AskBeforeDownloadNotifier extends Notifier<bool> {
  static const _key = 'ask_before_download';

  @override
  bool build() => false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}

final askBeforeDownloadProvider =
    NotifierProvider<AskBeforeDownloadNotifier, bool>(
  AskBeforeDownloadNotifier.new,
);
