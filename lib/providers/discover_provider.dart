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
    final path = await ref
        .read(registryServiceProvider)
        .downloadExtension(e, '$extDir/_dl');
    await ref.read(backendBridgeProvider).installExtension(path);
    ref.invalidate(extensionsProvider); // refresh installed list
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
