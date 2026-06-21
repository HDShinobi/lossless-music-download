import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/store_extension.dart';
import '../services/extension_registry_service.dart';
import 'extensions_provider.dart'; // backendBridgeProvider, appDirsProvider, extensionsProvider

const kDefaultAggregatorUrl =
    'https://raw.githubusercontent.com/HDShinobi/lossless-music-registry/main/repos.json';

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

final registryServiceProvider = Provider<ExtensionRegistryService>(
  (ref) => ExtensionRegistryService(ref.watch(httpClientProvider)),
);

class AggregatorUrlNotifier extends Notifier<String> {
  static const _key = 'aggregator_url';

  @override
  String build() => kDefaultAggregatorUrl;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getString(_key) ?? kDefaultAggregatorUrl;
  }

  Future<void> set(String url) async {
    state = url;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, url);
  }
}

final aggregatorUrlProvider =
    NotifierProvider<AggregatorUrlNotifier, String>(AggregatorUrlNotifier.new);

class DiscoverController extends AsyncNotifier<List<StoreExtension>> {
  @override
  Future<List<StoreExtension>> build() => ref
      .watch(registryServiceProvider)
      .fetchCatalog(ref.watch(aggregatorUrlProvider));

  Future<void> install(StoreExtension e) async {
    final (extDir, _) = await ref.read(appDirsProvider);
    final bridge = ref.read(backendBridgeProvider);
    final path = await ref
        .read(registryServiceProvider)
        .downloadExtension(e, '$extDir/_dl');
    try {
      final resultJson = await bridge.installExtension(path);
      // The backend installs new extensions DISABLED by default. Since the user
      // explicitly chose to install this source, enable it immediately so it is
      // usable without a second manual toggle. This also persists `_enabled=true`,
      // so the extension comes back enabled after an app restart.
      final id = _installedId(resultJson) ?? e.id;
      if (id.isNotEmpty) {
        await bridge.setExtensionEnabled(id, true);
      }
      ref.invalidate(extensionsProvider); // refresh installed list
    } catch (_) {
      try { await File(path).delete(); } catch (_) {}
      rethrow;
    }
  }

  /// Extracts the extension id from the JSON returned by `installExtension`
  /// (the authoritative manifest name). Returns null if it cannot be parsed.
  String? _installedId(String? installResultJson) {
    if (installResultJson == null || installResultJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(installResultJson);
      if (decoded is Map && decoded['id'] != null) {
        final id = decoded['id'].toString();
        return id.isEmpty ? null : id;
      }
    } catch (_) {}
    return null;
  }

  Future<void> setAggregatorUrl(String url) async {
    await ref.read(aggregatorUrlProvider.notifier).set(url);
    ref.invalidateSelf(); // refetch catalog from new URL
  }
}

final discoverProvider =
    AsyncNotifierProvider<DiscoverController, List<StoreExtension>>(
  DiscoverController.new,
);
