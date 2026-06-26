import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/metadata_resolver.dart';

void main() {
  group('pickBestEntity', () {
    test('prefers an exact (case-insensitive) name match', () {
      final candidates = [
        {'id': '1', 'name': 'Taylor Swift Tribute'},
        {'id': '2', 'name': 'taylor swift'},
        {'id': '3', 'name': 'Tay'},
      ];
      expect(pickBestEntity(candidates, 'Taylor Swift')!['id'], '2');
    });

    test('falls back to the first candidate when no exact match', () {
      final candidates = [
        {'id': '9', 'name': 'Taylor Swift Karaoke'},
        {'id': '8', 'name': 'Something else'},
      ];
      // Search results are relevance-ranked; take the top one.
      expect(pickBestEntity(candidates, 'Taylor Swift')!['id'], '9');
    });

    test('ignores candidates with an empty id', () {
      final candidates = [
        {'id': '', 'name': 'Taylor Swift'},
        {'id': '5', 'name': 'Taylor Swift'},
      ];
      expect(pickBestEntity(candidates, 'Taylor Swift')!['id'], '5');
    });

    test('returns null for an empty candidate list', () {
      expect(pickBestEntity([], 'X'), isNull);
    });
  });

  group('entityRouteId', () {
    test('builds provider:id from the entity provider_id', () {
      final id = entityRouteId(
        {'id': '12345', 'provider_id': 'deezer'},
        fallbackProvider: 'qobuz',
      );
      expect(id, 'deezer:12345');
    });

    test('uses the fallback provider when provider_id is absent', () {
      final id = entityRouteId({'id': '777'}, fallbackProvider: 'qobuz');
      expect(id, 'qobuz:777');
    });

    test('returns null when the id is empty', () {
      expect(entityRouteId({'id': '', 'provider_id': 'deezer'}), isNull);
    });

    test('returns a bare id when no provider is known', () {
      expect(entityRouteId({'id': '42'}), '42');
    });
  });
}
