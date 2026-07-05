import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'extensions_provider.dart';

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
      // The startup push (see pushCurrent) may have already fired before this
      // persisted value finished loading (it deliberately doesn't set
      // _explicitlySet so it can't suppress this load) — push again now that
      // we know the real persisted pool, so native doesn't stay stuck on the
      // interim "all" push.
      await _pushToNative(state);
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
    await _pushToNative(normalized);
  }

  /// Re-pushes the current pool to native without changing it. Used at
  /// startup so the engine reflects the pool as soon as possible.
  ///
  /// Deliberately does NOT go through [set] / set [_explicitlySet]: at app
  /// boot this typically runs before build()'s async persisted-value load
  /// (above) has resolved, so `state` here may still be the initial `null`.
  /// If we routed through [set], its synchronous `_explicitlySet = true`
  /// would win the race and permanently block the persisted load from ever
  /// applying, silently discarding the user's saved pool on every launch.
  Future<void> pushCurrent() => _pushToNative(state);

  /// Pushes to native so the Go engine's fallback pool matches the UI. For
  /// "all" (null) we resolve the current enabled-download-provider ids so
  /// the engine has a concrete list; this is non-fatal on failure since the
  /// engine keeps its last-known pool / default otherwise.
  Future<void> _pushToNative(List<String>? normalized) async {
    final toPush = normalized ?? _allEnabledDownloadProviderIds();
    // Never push an empty list to native. At the Go JSON boundary
    // (SetExtensionFallbackProviderIDsJSON), "[]" is NOT the same as "all":
    // it unmarshals to a non-nil empty slice, which the engine treats as
    // "no provider is in the fallback pool" and disables fallback for
    // everyone. Only a blank string resets the engine to its nil/"all"
    // default. `toPush` is empty here exactly when we have no explicit user
    // pool AND extensions haven't loaded yet (cold start) — in that case the
    // engine is still at its correct nil/"all" default, so skipping this
    // push is a no-op, not a lost update. Do NOT "simplify" this guard away.
    if (toPush.isEmpty) return;
    final bridge = ref.read(backendBridgeProvider);
    try {
      await bridge.setDownloadFallbackProviderIds(toPush);
    } catch (_) {
      // Non-fatal: engine keeps its last-known pool / default.
    }
  }

  List<String> _allEnabledDownloadProviderIds() =>
      (ref.read(extensionsProvider).value ?? const [])
          .where((e) => e.enabled && e.hasDownloadProvider)
          .map((e) => e.id)
          .toList();
}

final fallbackPoolProvider =
    NotifierProvider<FallbackPoolNotifier, List<String>?>(
  FallbackPoolNotifier.new,
);
