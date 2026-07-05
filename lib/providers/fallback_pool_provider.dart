import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user-chosen fallback provider-id pool. `null` means "all enabled
/// download providers" (the Go engine's default when no explicit pool is set).
class FallbackPoolNotifier extends Notifier<List<String>?> {
  static const _key = 'download_fallback_provider_ids';
  bool _explicitlySet = false;

  @override
  List<String>? build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (!ref.mounted || _explicitlySet) return;
      final raw = p.getString(_key);
      if (raw == null) return;
      state = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    });
    return null;
  }

  /// Persists the pool. An empty list is treated as `null` (all providers) and
  /// removes the stored key, so we never push an empty list to native.
  Future<void> set(List<String>? ids) async {
    _explicitlySet = true;
    final normalized = (ids == null || ids.isEmpty) ? null : ids;
    state = normalized;
    final p = await SharedPreferences.getInstance();
    if (normalized == null) {
      await p.remove(_key);
    } else {
      await p.setString(_key, jsonEncode(normalized));
    }
  }
}

final fallbackPoolProvider =
    NotifierProvider<FallbackPoolNotifier, List<String>?>(
  FallbackPoolNotifier.new,
);
