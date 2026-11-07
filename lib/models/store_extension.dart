class StoreExtension {
  final String id, displayName, version, description, category, downloadUrl, sourceName;
  final String? iconUrl;

  /// Minimum upstream engine version required (registry `min_app_version`),
  /// or null when unspecified. Used to gate installs and updates.
  final String? minAppVersion;

  const StoreExtension({
    required this.id,
    required this.displayName,
    required this.version,
    required this.description,
    required this.category,
    required this.downloadUrl,
    required this.sourceName,
    this.iconUrl,
    this.minAppVersion,
  });

  factory StoreExtension.fromRegistryJson(Map<String, dynamic> j, String sourceName) =>
      StoreExtension(
        id: (j['id'] ?? '').toString(),
        displayName: (j['display_name'] ?? j['name'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        category: (j['category'] ?? 'utility').toString(),
        downloadUrl: (j['download_url'] ?? '').toString(),
        iconUrl: j['icon_url']?.toString(),
        minAppVersion: (j['min_app_version'] ?? j['minAppVersion'])?.toString(),
        sourceName: sourceName,
      );
}
