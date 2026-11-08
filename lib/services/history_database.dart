import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/track.dart';
import '../models/library_entry.dart';

String _text(String? value) => (value ?? '').trim().toLowerCase();
String _isrc(String? value) =>
    (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[-\s]'), '');
String _match(Track track) =>
    track.name.trim().isEmpty || track.artists.trim().isEmpty
    ? ''
    : '${_text(track.name)}|${_text(track.artists)}';

// Provider IDs belong to the metadata source, not the fallback that delivered
// the audio. Never compare a Qobuz ID against an unrelated service's ID.
({String source, String id}) _identity(Track track) {
  final separator = track.id.indexOf(':');
  final source = _text(track.source).isNotEmpty
      ? _text(track.source)
      : separator > 0
      ? _text(track.id.substring(0, separator))
      : '';
  if (source.isEmpty ||
      source == 'unknown' ||
      source == 'library_scan' ||
      source == 'library') {
    return (source: source == 'library_scan' ? source : '', id: '');
  }
  return (
    source: source,
    id: separator > 0
        ? track.id.substring(separator + 1).trim()
        : track.id.trim(),
  );
}

/// Android filesystem aliases only. Keep case: Android paths are case sensitive.
Set<String> historyPathKeys(String path) {
  var value = path.trim();
  final uri = Uri.tryParse(value);
  if (uri?.scheme == 'file') value = uri!.toFilePath();
  if (uri?.host == 'com.android.externalstorage.documents' &&
      uri!.pathSegments.contains('document')) {
    final id = uri.pathSegments.last;
    if (id.startsWith('primary:')) {
      value = '/storage/emulated/0/${id.substring(8)}';
    }
  }
  const aliases = ['/storage/emulated/0', '/sdcard', '/storage/self/primary'];
  final keys = <String>{value};
  for (final alias in aliases) {
    if (value == alias || value.startsWith('$alias/')) {
      final suffix = value.substring(alias.length);
      keys.addAll(aliases.map((a) => '$a$suffix'));
      break;
    }
  }
  return keys;
}

Future<String?> _existingPath(String path) async {
  for (final key in historyPathKeys(path)) {
    if (!key.startsWith('/')) continue;
    try {
      if (await File(key).exists()) return key;
    } on FileSystemException catch (_) {
      // Revoked access is a missing candidate, not evidence of a duplicate.
    }
  }
  return null;
}

class HistoryEntry {
  final String id;
  final Track track;
  final String service;
  final String filePath;
  final int? fileSize;
  final String? quality;
  final DateTime downloadedAt;

  const HistoryEntry({
    required this.id,
    required this.track,
    required this.service,
    required this.filePath,
    required this.downloadedAt,
    this.fileSize,
    this.quality,
  });

  Map<String, Object?> toRow() {
    final identity = _identity(track);
    return {
      'id': id,
      'track_id': track.id,
      'source': identity.source,
      'provider_track_id': identity.id,
      'service': service,
      'isrc': track.isrc,
      'title': track.name,
      'artists': track.artists,
      'album': track.albumName,
      'album_artist': track.albumArtist,
      'track_number': track.trackNumber,
      'disc_number': track.discNumber,
      'total_discs': track.totalDiscs,
      'release_date': track.releaseDate,
      'playlist_position': track.playlistPosition,
      'duration_ms': track.durationMs,
      'quality': quality,
      'file_path': filePath,
      'file_size': fileSize,
      'downloaded_at': downloadedAt.millisecondsSinceEpoch,
      'cover_url': track.coverUrl,
      'isrc_norm': _isrc(track.isrc),
      'match_key': _match(track),
      'search_text': '${_text(track.name)} ${_text(track.artists)}',
    };
  }

  factory HistoryEntry.fromRow(Map<String, Object?> row) => HistoryEntry(
    id: row['id'] as String,
    track: Track(
      id: row['track_id'] as String? ?? '',
      source: row['source'] as String?,
      name: row['title'] as String,
      artists: row['artists'] as String,
      isrc: row['isrc'] as String?,
      albumName: row['album'] as String?,
      albumArtist: row['album_artist'] as String?,
      coverUrl: row['cover_url'] as String?,
      trackNumber: row['track_number'] as int?,
      discNumber: row['disc_number'] as int?,
      totalDiscs: row['total_discs'] as int?,
      releaseDate: row['release_date'] as String?,
      playlistPosition: row['playlist_position'] as int?,
      durationMs: row['duration_ms'] as int?,
    ),
    service: row['service'] as String,
    filePath: row['file_path'] as String,
    fileSize: row['file_size'] as int?,
    quality: row['quality'] as String?,
    downloadedAt: DateTime.fromMillisecondsSinceEpoch(
      row['downloaded_at'] as int,
    ),
  );
}

/// Own schema versioning: this reduced Android database is not upstream's DB.
/// v1 holds metadata; v2 adds lookups; v3 repairs identities; v4 retains
/// the disc/date/playlist fields needed to reapply download templates.
class HistoryDatabase {
  static const version = 4;
  final String path;
  final DatabaseFactory? factory;
  Future<Database>? _opening;
  HistoryDatabase({required this.path, this.factory});

  Future<Database> get database => _opening ??= _open();
  Future<Database> _open() async {
    try {
      return await (factory ?? databaseFactory).openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, v) async {
            await createV1(db, 1);
            await _upgrade(db, 1, v);
          },
          onUpgrade: _upgrade,
        ),
      );
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> createV1(Database db, int version) async {
    await db.execute('''CREATE TABLE history (
      id TEXT PRIMARY KEY, track_id TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT '', provider_track_id TEXT NOT NULL DEFAULT '',
      service TEXT NOT NULL, isrc TEXT, title TEXT NOT NULL, artists TEXT NOT NULL,
      album TEXT, album_artist TEXT, track_number INTEGER, disc_number INTEGER,
      duration_ms INTEGER, quality TEXT, file_path TEXT NOT NULL, file_size INTEGER,
      downloaded_at INTEGER NOT NULL, cover_url TEXT)''');
    await db.execute(
      'CREATE TABLE history_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static Future<void> _upgrade(Database db, int old, int next) async {
    if (old < 2) {
      await db.execute(
        "ALTER TABLE history ADD COLUMN isrc_norm TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE history ADD COLUMN match_key TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE history ADD COLUMN search_text TEXT NOT NULL DEFAULT ''",
      );
      // Bounded pages avoid materializing a restored database in memory.
      String after = '';
      while (true) {
        final rows = await db.query(
          'history',
          where: 'id > ?',
          whereArgs: [after],
          orderBy: 'id',
          limit: 256,
        );
        if (rows.isEmpty) break;
        final batch = db.batch();
        for (final row in rows) {
          final entry = HistoryEntry.fromRow(row);
          batch.update(
            'history',
            {
              'isrc_norm': _isrc(entry.track.isrc),
              'match_key': _match(entry.track),
              'search_text':
                  '${_text(entry.track.name)} ${_text(entry.track.artists)}',
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );
        }
        await batch.commit(noResult: true);
        after = rows.last['id'] as String;
      }
      await db.execute(
        'CREATE INDEX history_provider ON history(source, provider_track_id)',
      );
      await db.execute('CREATE INDEX history_isrc ON history(isrc_norm)');
      await db.execute('CREATE INDEX history_match ON history(match_key)');
      await db.execute(
        'CREATE INDEX history_added ON history(downloaded_at DESC, id DESC)',
      );
      await db.execute('CREATE INDEX history_path ON history(file_path)');
    }
    if (old < 4 && next >= 4) {
      await db.execute('ALTER TABLE history ADD COLUMN total_discs INTEGER');
      await db.execute('ALTER TABLE history ADD COLUMN release_date TEXT');
      await db.execute('ALTER TABLE history ADD COLUMN playlist_position INTEGER');
    }
    if (old < 3) {
      // v2 guessed Spotify for bare IDs; their provenance cannot be recovered.
      await db.execute(
        "UPDATE history SET source = '', provider_track_id = '' WHERE source = 'spotify' AND instr(track_id, ':') = 0",
      );
      await db.execute(
        "UPDATE history SET source = 'library_scan', provider_track_id = '' WHERE id LIKE 'scan:%' OR service = 'library'",
      );
      await db.execute(
        "UPDATE history SET provider_track_id = '' WHERE source IN ('', 'unknown', 'library_scan')",
      );
    }
  }

  /// Compare-and-set: a stale preview must never relink a changed history row.
  Future<bool> updateFilePath(String id, String expected, String target) async =>
      await (await database).update('history', {'file_path': target},
        where: 'id = ? AND file_path = ?', whereArgs: [id, expected]) == 1;

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  Future<void> upsert(HistoryEntry entry) async {
    if (entry.filePath.trim().isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      // A preflight/engine file-exists result may use a new queue item ID.
      // Keep a single physical-file row and replace scan-only metadata.
      await txn.delete(
        'history',
        where: 'file_path = ? AND id != ?',
        whereArgs: [entry.filePath, entry.id],
      );
      await txn.insert(
        'history',
        entry.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Refresh only rows owning this physical file. Keep provider ID, service,
  /// timestamp and quality; rebuild all indexed lookup/search values.
  Future<void> updateReEnriched(String oldPath, Map<String, dynamic> result) async {
    final metadata = result['enriched_metadata'];
    final tags = metadata is Map ? metadata : const {};
    final newPath = result['file_path'] as String?;
    final aliases = historyPathKeys(oldPath).toList();
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('history',
        where: 'file_path IN (${List.filled(aliases.length, '?').join(',')})',
        whereArgs: aliases);
      for (final row in rows) {
        final updated = Map<String, Object?>.from(row);
        const fields = {'track_name': 'title', 'artist_name': 'artists',
          'album_name': 'album', 'album_artist': 'album_artist', 'isrc': 'isrc',
          'track_number': 'track_number', 'disc_number': 'disc_number',
          'duration_ms': 'duration_ms', 'cover_url': 'cover_url',
          'total_discs': 'total_discs', 'release_date': 'release_date'};
        for (final field in fields.entries) {
          final value = tags[field.key];
          if (value is String && value.trim().isNotEmpty || value is num && value > 0) {
            updated[field.value] = value;
          }
        }
        if (newPath != null && newPath.trim().isNotEmpty) updated['file_path'] = newPath;
        final entry = HistoryEntry.fromRow(updated);
        await txn.update('history', entry.toRow(), where: 'id = ?', whereArgs: [entry.id]);
      }
    });
  }

  Future<List<HistoryEntry>> list({
    String search = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final query = _text(search);
    final rows = await (await database).query(
      'history',
      where: query.isEmpty ? null : "instr(search_text, ?) > 0",
      whereArgs: query.isEmpty ? null : [query],
      orderBy: 'downloaded_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(HistoryEntry.fromRow).toList();
  }

  Future<void> remove(String id) async =>
      (await database).delete('history', where: 'id = ?', whereArgs: [id]);

  Future<HistoryEntry?> find(Track track, {bool strict = false}) async =>
      (await findBatch([track], strict: strict)).single;

  /// One indexed query per <=64 requests, then one stat per distinct candidate.
  /// Priority remains provider+source, ISRC, title/artist even when a newer
  /// candidate is stale. Strict pre-download lookup excludes the text match.
  /// Album/duration guard only the weaker indicator/local-playback match.
  Future<List<HistoryEntry?>> findBatch(
    List<Track> tracks, {
    bool strict = false,
  }) async {
    if (tracks.isEmpty) return [];
    final db = await database;
    final results = <HistoryEntry?>[];
    final exists = <String, String?>{};
    for (var start = 0; start < tracks.length; start += 64) {
      final chunk = tracks.skip(start).take(64).toList();
      final clauses = <String>[];
      final args = <Object?>[];
      for (final track in chunk) {
        final identity = _identity(track);
        if (identity.id.isNotEmpty && identity.source.isNotEmpty) {
          clauses.add('(source = ? AND provider_track_id = ?)');
          args.addAll([identity.source, identity.id]);
        }
        if (_isrc(track.isrc).isNotEmpty) {
          clauses.add('isrc_norm = ?');
          args.add(_isrc(track.isrc));
        }
        if (!strict && _match(track).isNotEmpty) {
          clauses.add('match_key = ?');
          args.add(_match(track));
        }
      }
      final rows = clauses.isEmpty
          ? <Map<String, Object?>>[]
          : await db.query(
              'history',
              where: clauses.join(' OR '),
              whereArgs: args,
              orderBy: 'downloaded_at DESC, id DESC',
            );
      final entries = rows.map(HistoryEntry.fromRow).toList();
      for (final track in chunk) {
        final identity = _identity(track);
        HistoryEntry? found;
        for (var rank = 0; rank < (strict ? 2 : 3) && found == null; rank++) {
          for (final entry in entries) {
            final other = _identity(entry.track);
            final matches = switch (rank) {
              0 =>
                identity.source.isNotEmpty &&
                    identity.id.isNotEmpty &&
                    other.source != 'library_scan' &&
                    identity == other,
              1 =>
                _isrc(track.isrc).isNotEmpty &&
                    _isrc(track.isrc) == _isrc(entry.track.isrc),
              _ =>
                _match(track).isNotEmpty &&
                    _match(track) == _match(entry.track) &&
                    (_text(track.albumName).isEmpty ||
                        _text(entry.track.albumName).isEmpty ||
                        _text(track.albumName) ==
                            _text(entry.track.albumName)) &&
                    (track.durationMs == null ||
                        entry.track.durationMs == null ||
                        (track.durationMs! - entry.track.durationMs!).abs() <=
                            2000),
            };
            if (!matches) continue;
            if (!exists.containsKey(entry.filePath)) {
              exists[entry.filePath] = await _existingPath(entry.filePath);
            }
            final actual = exists[entry.filePath];
            if (actual == null) continue;
            if (actual != entry.filePath) await _relocateRow(db, entry, actual);
            found = HistoryEntry.fromRow({
              ...entry.toRow(),
              'file_path': actual,
            });
            break;
          }
        }
        results.add(found);
      }
    }
    return results;
  }

  Future<int> _relocateRow(
    DatabaseExecutor db,
    HistoryEntry entry,
    String path,
  ) {
    final aliases = historyPathKeys(path).toList();
    return db.rawUpdate(
      'UPDATE history SET file_path = ? '
      'WHERE id = ? AND file_path = ? AND downloaded_at = ? '
      'AND NOT EXISTS (SELECT 1 FROM history owner WHERE owner.id != ? '
      'AND owner.file_path IN (${List.filled(aliases.length, '?').join(',')}))',
      [
        path,
        entry.id,
        entry.filePath,
        entry.downloadedAt.millisecondsSinceEpoch,
        entry.id,
        ...aliases,
      ],
    );
  }

  bool _sameScannedIdentity(HistoryEntry entry, LibraryEntry candidate) {
    final isrc = _isrc(entry.track.isrc);
    if (isrc.isNotEmpty && isrc == _isrc(candidate.isrc)) return true;
    if (candidate.tagsFromFallback) return false;
    final title = _text(entry.track.name);
    final artist = _text(entry.track.artists);
    final album = _text(entry.track.albumName);
    return title.isNotEmpty &&
        artist.isNotEmpty &&
        album.isNotEmpty &&
        title == _text(candidate.taggedTitle) &&
        artist == _text(candidate.taggedArtistName) &&
        album == _text(candidate.taggedAlbumName);
  }

  Future<int> relocate(
    String root, {
    int limit = 128,
    Iterable<LibraryEntry> scannedEntries = const [],
  }) async {
    final db = await database;
    final key = 'relocate:$root';
    final meta = await db.query(
      'history_meta',
      where: 'key = ?',
      whereArgs: [key],
    );
    final cursor = meta.isEmpty ? '' : meta.single['value'] as String;
    final rows = await db.query(
      'history',
      where: 'id > ?',
      whereArgs: [cursor],
      orderBy: 'id',
      limit: limit,
    );
    final entries = rows.map(HistoryEntry.fromRow).toList();
    await db.insert('history_meta', {
      'key': key,
      'value': entries.length < limit ? '' : entries.last.id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final missing = <HistoryEntry>[];
    var count = 0;
    for (final entry in entries) {
      final actual = await _existingPath(entry.filePath);
      if (actual == null) {
        missing.add(entry);
      } else if (actual != entry.filePath) {
        count += await _relocateRow(db, entry, actual);
      }
    }
    if (missing.isEmpty || !await Directory(root).exists()) return count;
    final byName = <String, List<LibraryEntry>>{};
    final names = missing.map((e) => e.filePath.split('/').last).toSet();
    for (final candidate in scannedEntries) {
      final name = candidate.path.split('/').last;
      if (names.contains(name) &&
          candidate.path.startsWith(
            '${root.replaceFirst(RegExp(r'/+$'), '')}/',
          )) {
        byName.putIfAbsent(name, () => []).add(candidate);
      }
    }
    for (final entry in missing) {
      final candidates = (byName[entry.filePath.split('/').last] ?? [])
          .where((candidate) => _sameScannedIdentity(entry, candidate))
          .toList();
      if (candidates.length == 1 &&
          await _existingPath(candidates.single.path) != null) {
        count += await _relocateRow(db, entry, candidates.single.path);
      }
    }
    return count;
  }

  Future<bool> hasPendingBackfill(String root) async {
    final rows = await (await database).query(
      'history_meta',
      where: 'key = ?',
      whereArgs: ['backfill:$root'],
      limit: 1,
    );
    return rows.isEmpty || rows.single['value'] != '\u0000done';
  }

  /// Seed scan results once per root, in path-ordered pages. The durable cursor
  /// also prevents a removed history row from reappearing on the next scan.
  Future<int> backfill(
    String root,
    List<HistoryEntry> entries, {
    int limit = 256,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final key = 'backfill:$root';
      final meta = await txn.query(
        'history_meta',
        where: 'key = ?',
        whereArgs: [key],
      );
      final cursor = meta.isEmpty ? '' : meta.single['value'] as String;
      if (cursor == '\u0000done') return 0;
      final remaining =
          entries.where((e) => e.filePath.compareTo(cursor) > 0).toList()
            ..sort((a, b) => a.filePath.compareTo(b.filePath));
      final page = remaining.take(limit).toList();
      var inserted = 0;
      for (final entry in page) {
        if (await _existingPath(entry.filePath) == null) continue;
        final existing = await txn.query(
          'history',
          columns: ['id'],
          where: 'file_path = ?',
          whereArgs: [entry.filePath],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final stat = await File(entry.filePath).stat();
        final row = entry.toRow();
        row['source'] = 'library_scan';
        row['provider_track_id'] = '';
        row['file_size'] = stat.size;
        if (entry.downloadedAt.millisecondsSinceEpoch == 0) {
          row['downloaded_at'] = stat.modified.millisecondsSinceEpoch;
        }
        await txn.insert(
          'history',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        inserted++;
      }
      await txn.insert('history_meta', {
        'key': key,
        'value': remaining.length <= limit ? '\u0000done' : page.last.filePath,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return inserted;
    });
  }
}
