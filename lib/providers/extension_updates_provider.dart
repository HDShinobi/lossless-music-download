import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  const ExtensionUpdate({
    required this.id,
    required this.displayName,
    required this.fromVersion,
    required this.toVersion,
    required this.storeExt,
  });
}

/// Pure: given [installed] extensions and the [catalog], returns the extensions
/// whose catalog version is newer than the installed one. Version comparison
/// reuses [isNewerVersion] (semver with build/prerelease suffixes ignored).
/// Catalog entries that aren't installed are ignored — this is about updating,
/// not discovering.
///
/// NOTE: the registry's `min_app_version` is SpotiFLAC-Mobile's version scheme
/// (4.x), which is unrelated to this fork's app version (0.x), so it is NOT
/// used to gate updates — comparing the two would flag every source as
/// incompatible.
List<ExtensionUpdate> computeExtensionUpdates(
  List<InstalledExtension> installed,
  List<StoreExtension> catalog,
) {
  final byId = {for (final e in catalog) e.id: e};
  final updates = <ExtensionUpdate>[];
  for (final ext in installed) {
    final store = byId[ext.id];
    if (store == null) continue;
    if (!isNewerVersion(store.version, ext.version)) continue;
    updates.add(ExtensionUpdate(
      id: ext.id,
      displayName: ext.displayName.isNotEmpty ? ext.displayName : ext.name,
      fromVersion: ext.version,
      toVersion: store.version,
      storeExt: store,
    ));
  }
  return updates;
}

/// Available extension updates, derived from the installed list and the
/// catalog. Empty while either source is still loading.
final extensionUpdatesProvider = Provider<List<ExtensionUpdate>>((ref) {
  final installed = ref.watch(extensionsProvider).value ?? const [];
  final catalog = ref.watch(discoverProvider).value ?? const [];
  return computeExtensionUpdates(installed, catalog);
});
