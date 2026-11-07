import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/track.dart';
import '../services/history_database.dart';

final historyDatabaseProvider = FutureProvider<HistoryDatabase>((ref) async {
  final directory = await getDatabasesPath();
  final history = HistoryDatabase(path: '$directory/download_history.db');
  ref.onDispose(() => unawaited(history.close()));
  return history;
});

class HistoryRevision extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final historyRevisionProvider = NotifierProvider<HistoryRevision, int>(
  HistoryRevision.new,
);

final downloadHistoryProvider = FutureProvider.autoDispose
    .family<List<HistoryEntry>, ({String search, int page})>((
      ref,
      request,
    ) async {
      ref.watch(historyRevisionProvider);
      final db = await ref.watch(historyDatabaseProvider.future);
      return db.list(
        search: request.search,
        limit: 100,
        offset: request.page * 100,
      );
    });

String historyLookupKey(Track track) => jsonEncode([
  track.id,
  track.source,
  track.isrc,
  track.name,
  track.artists,
  track.albumName,
  track.durationMs,
]);

/// Value equality keeps rebuilding screens from issuing the same batch again.
class HistoryLookupBatch {
  final List<Track> tracks;
  final String key;
  HistoryLookupBatch(Iterable<Track> tracks)
    : tracks = List.unmodifiable(tracks),
      key = jsonEncode(tracks.map(historyLookupKey).toList());
  @override
  bool operator ==(Object other) =>
      other is HistoryLookupBatch && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

final downloadedTracksProvider = FutureProvider.autoDispose
    .family<Set<String>, HistoryLookupBatch>((ref, batch) async {
      ref.watch(historyRevisionProvider);
      final db = await ref.watch(historyDatabaseProvider.future);
      final matches = await db.findBatch(batch.tracks);
      return {
        for (var i = 0; i < matches.length; i++)
          if (matches[i] != null) historyLookupKey(batch.tracks[i]),
      };
    });
