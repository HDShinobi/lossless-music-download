import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'extensions_provider.dart';

String _norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Picks the best entity from custom-search [candidates] for [wantedName]:
/// an exact (normalized) name match if present, otherwise the first candidate
/// with a non-empty id (search results are relevance-ranked). Null if none.
Map<String, dynamic>? pickBestEntity(
  List<Map<String, dynamic>> candidates,
  String wantedName,
) {
  final withId = candidates
      .where((c) => (c['id'] ?? '').toString().isNotEmpty)
      .toList();
  if (withId.isEmpty) return null;
  final want = _norm(wantedName);
  for (final c in withId) {
    if (_norm((c['name'] ?? '').toString()) == want) return c;
  }
  return withId.first;
}

/// Builds a `provider:id` route id from a resolved entity, used by the
/// artist/album screens. Returns null if the entity has no id. Falls back to a
/// bare id when neither the entity nor [fallbackProvider] names a provider.
String? entityRouteId(Map<String, dynamic> entity, {String? fallbackProvider}) {
  final id = (entity['id'] ?? '').toString();
  if (id.isEmpty) return null;
  final provider = (entity['provider_id'] ?? '').toString().trim().isNotEmpty
      ? entity['provider_id'].toString().trim()
      : (fallbackProvider?.trim().isNotEmpty ?? false)
          ? fallbackProvider!.trim()
          : '';
  return provider.isEmpty ? id : '$provider:$id';
}

/// Resolves an artist/album ID by name via the providers' custom (entity)
/// search — used when a track's metadata didn't carry the ID, so the
/// artist/album page can still be opened (SpotiFLAC-style on-demand lookup).
class MetadataResolver {
  MetadataResolver(this.ref);
  final Ref ref;

  /// Resolves a route id (`provider:id`) for [name] of kind [filter]
  /// ("artist"|"album"). [providerHint] (a track's source) is tried first.
  /// Returns null if nothing matched.
  Future<String?> resolve({
    required String name,
    required String filter,
    String? providerHint,
  }) async {
    if (name.trim().isEmpty) return null;
    final bridge = ref.read(backendBridgeProvider);

    // Build the provider try-order: the track's source first, then the rest.
    final providerIds = <String>[];
    if (providerHint != null && providerHint.trim().isNotEmpty) {
      providerIds.add(providerHint.trim());
    }
    for (final p in await bridge.getSearchProviders()) {
      final id = (p['id'] ?? '').toString();
      if (id.isNotEmpty && !providerIds.contains(id)) providerIds.add(id);
    }

    for (final provider in providerIds) {
      try {
        final results = await bridge.customSearch(
          provider,
          name,
          options: {'filter': filter, 'limit': 10},
        );
        final best = pickBestEntity(results, name);
        if (best != null) {
          final routeId = entityRouteId(best, fallbackProvider: provider);
          if (routeId != null) return routeId;
        }
      } catch (_) {
        // Try the next provider.
      }
    }
    return null;
  }
}

final metadataResolverProvider =
    Provider<MetadataResolver>((ref) => MetadataResolver(ref));
