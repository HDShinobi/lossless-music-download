import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_feed.dart';
import '../models/installed_extension.dart';
import 'extensions_provider.dart';

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

/// Resolves the active home-feed source, fetches its feed, and caches the
/// result (`home_feed_cache` + `home_feed_cache_ts`, 6h TTL) so cold starts
/// can show something instantly while a stale cache refreshes in the
/// background.
class HomeFeedController extends AsyncNotifier<List<HomeFeedSection>> {
  static const _cacheKey = 'home_feed_cache';
  static const _cacheTsKey = 'home_feed_cache_ts';
  static const _ttl = Duration(hours: 6);

  @override
  Future<List<HomeFeedSection>> build() async {
    // Re-resolve once the disk-loaded extension list is ready (cold start).
    final exts = await ref.watch(extensionsProvider.future);
    final source = ref.watch(homeFeedSourceProvider);
    final ext = _resolve(exts, source);
    if (ext == null) return const [];

    final p = await SharedPreferences.getInstance();
    final cached = _readCache(p);
    final ts = p.getInt(_cacheTsKey) ?? 0;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(ts);
    final fresh = ts != 0 && DateTime.now().difference(cachedAt) < _ttl;

    if (cached.isNotEmpty && fresh) return cached; // fresh: skip network
    if (cached.isNotEmpty) {
      // stale: show cache immediately, refresh in the background
      unawaited(_fetchAndStore(ext.id));
      return cached;
    }
    return _fetchAndStore(ext.id); // none: fetch now
  }

  InstalledExtension? _resolve(List<InstalledExtension> exts, String? source) {
    if (source == homeFeedSourceOff) return null;
    final capable = exts.where((e) => e.enabled && e.hasHomeFeed).toList();
    if (source != null && source.isNotEmpty) {
      return capable.where((e) => e.id == source).firstOrNull;
    }
    return capable.firstOrNull;
  }

  Future<List<HomeFeedSection>> _fetchAndStore(String extId) async {
    try {
      final env = await ref.read(backendBridgeProvider).getExtensionHomeFeed(extId);
      final sections = parseHomeFeed(env);
      if (sections.isNotEmpty) {
        final p = await SharedPreferences.getInstance();
        await p.setString(_cacheKey, jsonEncode(env));
        await p.setInt(_cacheTsKey, DateTime.now().millisecondsSinceEpoch);
        state = AsyncData(sections);
      }
      return sections;
    } catch (_) {
      return state.value ?? const [];
    }
  }

  List<HomeFeedSection> _readCache(SharedPreferences p) {
    final raw = p.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return parseHomeFeed(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return const [];
    }
  }

  /// Forces a fresh fetch, bypassing the cache freshness check.
  Future<void> refresh() async {
    final exts = ref.read(extensionsProvider).value ?? const [];
    final ext = _resolve(exts, ref.read(homeFeedSourceProvider));
    if (ext == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = AsyncData(await _fetchAndStore(ext.id));
  }
}

final homeFeedControllerProvider =
    AsyncNotifierProvider<HomeFeedController, List<HomeFeedSection>>(
  HomeFeedController.new,
);
