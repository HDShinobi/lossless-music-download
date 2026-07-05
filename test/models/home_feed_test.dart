import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/home_feed.dart';

void main() {
  test('parseHomeFeed returns [] when success != true', () {
    expect(parseHomeFeed(null), isEmpty);
    expect(parseHomeFeed({'success': false, 'error': 'x', 'sections': [{'title': 'a', 'items': []}]}), isEmpty);
  });

  test('parses sections + items with name field', () {
    final sections = parseHomeFeed({
      'success': true,
      'sections': [
        {'uri': 's1', 'title': 'New releases', 'items': [
          {'id': 't1', 'type': 'track', 'name': 'Song', 'artists': 'A', 'cover_url': 'c', 'provider_id': 'ytmusic', 'album_id': 'al1', 'album_name': 'Alb', 'duration_ms': 1000},
        ]},
      ],
    });
    expect(sections.single.title, 'New releases');
    final item = sections.single.items.single;
    expect(item.name, 'Song');
    expect(item.providerId, 'ytmusic');
    expect(item.albumId, 'al1');
  });

  test('toTrack maps name→name, provider_id→source, album fields', () {
    final item = HomeFeedItem(id: 't1', uri: 'u', type: 'track', name: 'Song',
        artists: 'A', coverUrl: 'c', albumId: 'al1', albumName: 'Alb',
        durationMs: 1000, providerId: 'ytmusic');
    final t = item.toTrack();
    expect(t.name, 'Song');
    expect(t.artists, 'A');
    expect(t.source, 'ytmusic');
    expect(t.albumId, 'al1');
  });

  test('skips unparseable items, keeps the rest', () {
    final sections = parseHomeFeed({'success': true, 'sections': [
      {'title': 's', 'items': [ 42, {'id': 't', 'type': 'track', 'name': 'ok', 'artists': ''} ]},
    ]});
    expect(sections.single.items.length, 1);
    expect(sections.single.items.single.name, 'ok');
  });
}
