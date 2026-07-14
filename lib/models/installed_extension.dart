/// A downloadable audio quality the source declares in its manifest
/// (`quality_options`). The [id] is the token the backend matches against
/// when honouring a user's quality choice (see extension_providers.go).
class ExtensionQualityOption {
  final String id, label, description;

  const ExtensionQualityOption({
    required this.id,
    required this.label,
    this.description = '',
  });

  factory ExtensionQualityOption.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final label = (j['label'] ?? '').toString();
    return ExtensionQualityOption(
      id: id,
      label: label.isNotEmpty ? label : id,
      description: (j['description'] ?? '').toString(),
    );
  }
}

class InstalledExtension {
  final String id, name, version, displayName, description, status;
  final String? iconPath;
  final bool enabled, hasMetadataProvider, hasDownloadProvider, hasLyricsProvider;
  final List<String> types, permissions;
  final Map<String, dynamic> capabilities;
  final List<ExtensionQualityOption> qualityOptions;

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
    this.capabilities = const {},
    this.qualityOptions = const [],
  });

  bool get hasHomeFeed => capabilities['homeFeed'] == true;

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
        capabilities: (j['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {},
        qualityOptions: (j['quality_options'] as List?)
                ?.whereType<Map>()
                .map((q) => ExtensionQualityOption.fromJson(q.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}
