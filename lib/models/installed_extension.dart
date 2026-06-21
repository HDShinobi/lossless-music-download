class InstalledExtension {
  final String id, name, version, displayName, description, status;
  final String? iconPath;
  final bool enabled, hasMetadataProvider, hasDownloadProvider, hasLyricsProvider;
  final List<String> types, permissions;

  const InstalledExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.enabled,
    required this.types,
    required this.displayName,
    required this.description,
    required this.status,
    this.iconPath,
    required this.permissions,
    required this.hasMetadataProvider,
    required this.hasDownloadProvider,
    required this.hasLyricsProvider,
  });

  factory InstalledExtension.fromJson(Map<String, dynamic> j) => InstalledExtension(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        enabled: j['enabled'] == true,
        types: (j['types'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        displayName: (j['display_name'] ?? j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        iconPath: j['icon_path']?.toString(),
        permissions: (j['permissions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        hasMetadataProvider: j['has_metadata_provider'] == true,
        hasDownloadProvider: j['has_download_provider'] == true,
        hasLyricsProvider: j['has_lyrics_provider'] == true,
      );
}
