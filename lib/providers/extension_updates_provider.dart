import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/installed_extension.dart';
import '../models/store_extension.dart';
import '../services/update_checker.dart' show isNewerVersion;
import 'discover_provider.dart';
import 'extensions_provider.dart';

/// An installed extension that has a newer version available in the catalog.
class ExtensionUpdate {
  final String id;
  final String displayName;
  final String fromVersion;
  final String toVersion;
  final StoreExtension storeExt;

  /// False when the catalog entry's `min_app_version` is newer than the
  /// running app — the update is shown as incompatible instead of applied.
  final bool compatible;

  const ExtensionUpdate({
    required this.id,
    required this.displayName,
    required this.fromVersion,
    required this.toVersion,
    required this.storeExt,
    required this.compatible,
  });
}

/// Pure: given [installed] extensions, the [catalog], and the running
/// [appVersion], returns the extensions whose catalog version is newer than
/// the installed one. Version comparison reuses [isNewerVersion] (semver with
/// build/prerelease suffixes ignored). Catalog entries that aren't installed
/// are ignored — this is about updating, not discovering.
///
/// An empty [appVersion] (package info not yet loaded) is treated as
/// compatible so updates aren't transiently hidden during startup.
List<ExtensionUpdate> computeExtensionUpdates(
  List<InstalledExtension> installed,
  List<StoreExtension> catalog,
  String appVersion,
) {
  final byId = {for (final e in catalog) e.id: e};
  final updates = <ExtensionUpdate>[];
  for (final ext in installed) {
    final store = byId[ext.id];
    if (store == null) continue;
    if (!isNewerVersion(store.version, ext.version)) continue;
    final minApp = store.minAppVersion;
    final compatible = appVersion.isEmpty ||
        minApp == null ||
        minApp.isEmpty ||
        !isNewerVersion(minApp, appVersion);
    updates.add(ExtensionUpdate(
      id: ext.id,
      displayName: ext.displayName.isNotEmpty ? ext.displayName : ext.name,
      fromVersion: ext.version,
      toVersion: store.version,
      storeExt: store,
      compatible: compatible,
    ));
  }
  return updates;
}

/// Number of updates that can actually be applied on this app version.
int compatibleUpdateCount(List<ExtensionUpdate> updates) =>
    updates.where((u) => u.compatible).length;

/// Running app version (e.g. "0.5.0"); empty until package info resolves.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Available extension updates, derived from the installed list, the catalog,
/// and the app version. Empty while any source is still loading.
final extensionUpdatesProvider = Provider<List<ExtensionUpdate>>((ref) {
  final installed = ref.watch(extensionsProvider).value ?? const [];
  final catalog = ref.watch(discoverProvider).value ?? const [];
  final appVersion = ref.watch(appVersionProvider).value ?? '';
  return computeExtensionUpdates(installed, catalog, appVersion);
});
