import 'track.dart';

class HomeFeedItem {
  final String id;
  final String uri;
  final String type; // 'track' | 'album' | 'artist' | ...
  final String name;
  final String artists;
  final String? description;
  final String? coverUrl;
  final String? albumId;
  final String? albumName;
  final int? durationMs;
  final String providerId;

  const HomeFeedItem({
    required this.id,
    this.uri = '',
    required this.type,
    required this.name,
    this.artists = '',
    this.description,
    this.coverUrl,
    this.albumId,
    this.albumName,
    this.durationMs,
    this.providerId = '',
  });

  static HomeFeedItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = (j['id'] ?? '').toString();
    final name = (j['name'] ?? '').toString();
    if (id.isEmpty && name.isEmpty) return null;
    return HomeFeedItem(
      id: id,
      uri: (j['uri'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      name: name,
      artists: (j['artists'] ?? '').toString(),
      description: j['description']?.toString(),
      coverUrl: j['cover_url']?.toString(),
      albumId: j['album_id']?.toString(),
      albumName: j['album_name']?.toString(),
      durationMs: (j['duration_ms'] as num?)?.toInt(),
      providerId: (j['provider_id'] ?? '').toString(),
    );
  }

  /// Route id used by album/artist screens: provider-prefixed.
  String get routeId => providerId.isEmpty ? id : '$providerId:$id';

  Track toTrack() => Track(
        id: id,
        name: name,
        artists: artists,
        source: providerId,
        albumId: albumId,
        albumName: albumName,
        coverUrl: coverUrl,
        durationMs: durationMs,
      );
}

class HomeFeedSection {
  final String uri;
  final String title;
  final List<HomeFeedItem> items;
  const HomeFeedSection({this.uri = '', required this.title, required this.items});
}

/// Parses the `{success, sections:[{title, items:[...]}]}` envelope.
/// Returns `[]` when success is not true (a failure envelope is NOT a feed).
List<HomeFeedSection> parseHomeFeed(Map<String, dynamic>? envelope) {
  if (envelope == null || envelope['success'] != true) return const [];
  final rawSections = envelope['sections'];
  if (rawSections is! List) return const [];
  final out = <HomeFeedSection>[];
  for (final s in rawSections) {
    if (s is! Map) continue;
    final sm = s.cast<String, dynamic>();
    final items = <HomeFeedItem>[];
    final rawItems = sm['items'];
    if (rawItems is List) {
      for (final it in rawItems) {
        final parsed = HomeFeedItem.fromJson(it);
        if (parsed != null) items.add(parsed);
      }
    }
    if (items.isEmpty) continue;
    out.add(HomeFeedSection(
      uri: (sm['uri'] ?? '').toString(),
      title: (sm['title'] ?? '').toString(),
      items: items,
    ));
  }
  return out;
}
