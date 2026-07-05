import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sentinel: home feed explicitly disabled by the user.
const String homeFeedSourceOff = '__off__';

/// Selected home-feed source: null = auto (first enabled hasHomeFeed),
/// a specific extension id, or [homeFeedSourceOff] = disabled.
class HomeFeedSourceNotifier extends Notifier<String?> {
  static const _key = 'home_feed_source';
  bool _explicitlySet = false;

  @override
  String? build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) state = p.getString(_key);
    });
    return null;
  }

  Future<void> set(String? value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(_key);
    } else {
      await p.setString(_key, value);
    }
  }
}

final homeFeedSourceProvider =
    NotifierProvider<HomeFeedSourceNotifier, String?>(HomeFeedSourceNotifier.new);
