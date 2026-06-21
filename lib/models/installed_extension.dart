class InstalledExtension {
  final String id, name, version;
  final bool enabled;
  final List<String> types;
  const InstalledExtension({required this.id, required this.name, required this.version, required this.enabled, required this.types});
  factory InstalledExtension.fromJson(Map<String, dynamic> j) => InstalledExtension(
        id: (j['id'] ?? '').toString(),
        name: (j['displayName'] ?? j['name'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        enabled: j['enabled'] == true,
        types: (j['type'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
