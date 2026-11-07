import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/models/library_entry.dart';
import 'package:lossless_music_download/services/history_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late HistoryDatabase history;
  const song = Track(
    id: 'qobuz:42',
    source: 'qobuz',
    name: 'Song',
    artists: 'Artist',
    albumName: 'Album',
    durationMs: 180000,
    isrc: 'US-ABC-12-34567',
  );
  Future<HistoryEntry> add(String id, Track track, {String? path}) async {
    final file = File(path ?? '${dir.path}/$id.flac');
    await file.parent.create(recursive: true);
    await file.writeAsString('audio');
    final entry = HistoryEntry(
      id: id,
      track: track,
      service: 'qobuz',
      filePath: file.path,
      fileSize: 5,
      downloadedAt: DateTime(2026, 1, 1),
    );
    await history.upsert(entry);
    return entry;
  }

  LibraryEntry scanned(
    String path, {
    String? isrc = 'USABC1234567',
    String? title = 'Song',
    String artist = 'Artist',
    String? album = 'Album',
    bool fallback = false,
  }) => LibraryEntry(
    path: path,
    name: path.split('/').last,
    sizeBytes: 5,
    format: 'FLAC',
    verified: true,
    isrc: isrc,
    title: title,
    artistName: artist,
    albumName: album,
    tagsFromFallback: fallback,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('history_test_');
    history = HistoryDatabase(
      path: '${dir.path}/history.db',
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await history.close();
    await dir.delete(recursive: true);
  });
  test('unknown source never invents a Spotify provider key', () async {
    await add('unknown', const Track(id: '42', name: 'One', artists: 'A'));
    expect(
      await history.find(
        const Track(
          id: 'spotify:42',
          source: 'spotify',
          name: 'Two',
          artists: 'B',
        ),
      ),
      isNull,
    );
    final row = (await (await history.database).query('history')).single;
    expect(row['source'], isEmpty);
    expect(row['provider_track_id'], isEmpty);
  });
  test('basename alone cannot relocate a missing row', () async {
    final entry = await add('same', song);
    await File(entry.filePath).delete();
    final candidate = await File(
      '${dir.path}/other/same.flac',
    ).create(recursive: true);
    expect(
      await history.relocate(
        dir.path,
        scannedEntries: [
          scanned(candidate.path, isrc: null, artist: 'Other artist'),
        ],
      ),
      0,
    );
    expect(await history.find(song), isNull);
  });
  test('backfill marks scan origin and clears provider identity', () async {
    final file = await File('${dir.path}/seed.flac').writeAsString('audio');
    await history.backfill(dir.path, [
      HistoryEntry(
        id: 'seed',
        track: song,
        service: 'library',
        filePath: file.path,
        downloadedAt: DateTime.now(),
      ),
    ]);
    final row = (await (await history.database).query('history')).single;
    expect(row['source'], 'library_scan');
    expect(row['provider_track_id'], isEmpty);
  });
  test(
    'strict scan lookup allows ISRC but never provider or text identity',
    () async {
      final file = await File('${dir.path}/seed.flac').writeAsString('audio');
      await history.backfill(dir.path, [
        HistoryEntry(
          id: 'scan',
          track: song,
          service: 'library',
          filePath: file.path,
          downloadedAt: DateTime.now(),
        ),
      ]);
      expect(await history.find(song, strict: true), isNotNull);
      expect(
        await history.find(
          const Track(
            id: 'qobuz:42',
            source: 'qobuz',
            name: 'Other',
            artists: 'Other',
          ),
          strict: true,
        ),
        isNull,
      );
      const sameText = Track(
        id: 'qobuz:2',
        source: 'qobuz',
        name: 'Song',
        artists: 'Artist',
        albumName: 'Album',
        durationMs: 180000,
        isrc: 'DIFFERENT',
      );
      expect(await history.find(sameText), isNotNull);
      expect(await history.find(sameText, strict: true), isNull);
      await file.delete();
      expect(await history.find(song, strict: true), isNull);
    },
  );
  test('unknown bare IDs do not match each other at rank zero', () async {
    await add('unknown', const Track(id: '42', name: 'One', artists: 'A'));
    expect(
      await history.find(
        const Track(id: '42', name: 'Two', artists: 'B'),
        strict: true,
      ),
      isNull,
    );
    expect(
      await history.find(
        const Track(id: '42', source: 'deezer', name: 'Two', artists: 'B'),
        strict: true,
      ),
      isNull,
    );
  });
  test('relocation rejects a path already owned by another row', () async {
    final missing = await add('same', song);
    await File(missing.filePath).delete();
    final candidate = await add(
      'owner',
      song,
      path: '${dir.path}/music/same.flac',
    );
    expect(
      await history.relocate(
        dir.path,
        scannedEntries: [scanned(candidate.filePath)],
      ),
      0,
    );
    expect(
      (await history.list()).firstWhere((e) => e.id == 'same').filePath,
      missing.filePath,
    );
  });
  test('relocation accepts complete normalized tags without ISRC', () async {
    final missing = await add('same', song);
    final path = '${dir.path}/music/same.flac';
    await Directory('${dir.path}/music').create();
    await File(missing.filePath).rename(path);
    expect(
      await history.relocate(
        dir.path,
        scannedEntries: [
          scanned(
            path,
            isrc: null,
            title: ' song ',
            artist: 'ARTIST',
            album: ' album ',
          ),
        ],
      ),
      1,
    );
    expect((await history.find(song))?.filePath, path);
  });
  for (final fallback in [false, true]) {
    test(
      'relocation rejects ${fallback ? "folder fallback" : "incomplete"} tags',
      () async {
        final missing = await add('same', song);
        final path = '${dir.path}/music/same.flac';
        await Directory('${dir.path}/music').create();
        await File(missing.filePath).rename(path);
        expect(
          await history.relocate(
            dir.path,
            scannedEntries: [
              scanned(
                path,
                isrc: null,
                album: fallback ? 'Album' : null,
                fallback: fallback,
              ),
            ],
          ),
          0,
        );
        expect(await history.find(song), isNull);
      },
    );
  }
  test(
    'CRUD persists metadata, upserts final path, searches and removes only row',
    () async {
      final entry = await add('one', song);
      await history.upsert(
        HistoryEntry(
          id: 'one',
          track: song,
          service: 'tidal',
          filePath: entry.filePath,
          fileSize: 5,
          quality: 'FLAC',
          downloadedAt: DateTime(2026, 2),
        ),
      );
      await add('two', const Track(id: 'two', name: 'Other', artists: 'Else'));
      final rows = await history.list(search: 'ARTIST');
      expect(rows, hasLength(1));
      expect(rows.single.quality, 'FLAC');
      expect(rows.single.track.albumName, 'Album');
      expect((await history.list()).first.id, 'one');
      await history.remove('one');
      expect(await history.list(search: 'Song'), isEmpty);
      expect(await File(entry.filePath).exists(), isTrue);
    },
  );
  test(
    'lookup prefers provider identity, then ISRC, then text with album/duration guards',
    () async {
      final text = await add(
        'text',
        const Track(
          id: 'other',
          name: ' song ',
          artists: 'ARTIST',
          albumName: 'Album',
          durationMs: 181000,
        ),
      );
      final isrc = await add(
        'isrc',
        const Track(
          id: 'other2',
          name: 'Different',
          artists: 'Else',
          isrc: 'USABC1234567',
        ),
      );
      final provider = await add(
        'provider',
        const Track(
          id: 'qobuz:42',
          source: 'qobuz',
          name: 'Different',
          artists: 'Else',
        ),
      );
      expect((await history.find(song))?.id, provider.id);
      await File(provider.filePath).delete();
      expect((await history.find(song))?.id, isrc.id);
      await File(isrc.filePath).delete();
      expect((await history.find(song))?.id, text.id);
      expect(
        await history.find(
          const Track(
            id: '',
            name: 'Song',
            artists: 'Artist',
            albumName: 'Live',
          ),
        ),
        isNull,
      );
      expect(
        await history.find(
          const Track(
            id: '',
            name: 'Song',
            artists: 'Artist',
            durationMs: 200000,
          ),
        ),
        isNull,
      );
      expect(
        await history.find(
          const Track(
            id: 'tidal:42',
            source: 'tidal',
            name: 'Unknown',
            artists: 'Else',
          ),
        ),
        isNull,
      );
      expect(
        await history.findBatch([
          song,
          const Track(id: '', name: 'Unknown', artists: 'Else'),
        ]),
        [isA<HistoryEntry>(), null],
      );
    },
  );
  test(
    'v2 migration removes guessed identities and marks existing scan rows',
    () async {
      final legacy = await add(
        'legacy',
        const Track(id: '42', name: 'One', artists: 'A'),
      );
      final scan = await add('scan:old', song);
      final sql = await history.database;
      await sql.update(
        'history',
        {'source': 'spotify', 'provider_track_id': '42'},
        where: 'id = ?',
        whereArgs: [legacy.id],
      );
      await sql.setVersion(2);
      await history.close();
      history = HistoryDatabase(
        path: '${dir.path}/history.db',
        factory: databaseFactoryFfi,
      );
      final migrated = await history.database;
      final rows = await migrated.query('history', orderBy: 'id');
      expect(rows.first['source'], '');
      expect(rows.first['provider_track_id'], '');
      expect(rows.last['source'], 'library_scan');
      expect(rows.last['provider_track_id'], '');
      expect(
        await history.find(
          const Track(
            id: 'spotify:42',
            source: 'spotify',
            name: 'Different',
            artists: 'B',
          ),
          strict: true,
        ),
        isNull,
      );
      expect((await history.find(song, strict: true))?.filePath, scan.filePath);
    },
  );
  test(
    'migration from v1 preserves rows and creates normalized lookup indexes',
    () async {
      await history.close();
      final db = await databaseFactoryFfi.openDatabase(
        '${dir.path}/history.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: HistoryDatabase.createV1,
        ),
      );
      await db.insert('history', {
        'id': 'legacy',
        'track_id': 'qobuz:42',
        'source': 'qobuz',
        'provider_track_id': '42',
        'service': 'qobuz',
        'title': 'Song',
        'artists': 'Artist',
        'file_path': '${dir.path}/legacy.flac',
        'downloaded_at': 1,
        'isrc': 'us-abc-12-34567',
      });
      await db.close();
      await File('${dir.path}/legacy.flac').writeAsString('audio');
      expect((await history.find(song))?.id, 'legacy');
      final upgraded = await history.database;
      expect(await upgraded.getVersion(), HistoryDatabase.version);
      expect(
        (await upgraded.rawQuery(
          'PRAGMA index_list(history)',
        )).map((r) => r['name']),
        contains('history_isrc'),
      );
    },
  );
  test(
    'relocates missing paths, retains ambiguous basenames and never resurrects removed rows',
    () async {
      final entry = await add('moved', song);
      final moved = '${dir.path}/music/album/moved.flac';
      await Directory('${dir.path}/music/album').create(recursive: true);
      await File(entry.filePath).rename(moved);
      expect(
        await history.relocate(
          '${dir.path}/music',
          scannedEntries: [scanned(moved)],
        ),
        1,
      );
      expect((await history.find(song))?.filePath, moved);
      await history.remove(entry.id);
      expect(await history.relocate('${dir.path}/music'), 0);
      expect(await history.list(), isEmpty);
    },
  );
  test(
    'search handles Vietnamese case and literal SQL wildcard characters',
    () async {
      await add(
        'vietnamese',
        const Track(id: 'vi', name: 'ĐÊM % _', artists: 'ĐẶNG'),
      );
      expect(await history.list(search: 'đêm'), hasLength(1));
      expect(await history.list(search: 'đặng'), hasLength(1));
      expect(await history.list(search: '% _'), hasLength(1));
      expect(await history.list(search: '%missing'), isEmpty);
    },
  );
  test(
    'ambiguous basename is not relocated; path aliases keep Android case',
    () async {
      final entry = await add('same', song);
      await File(entry.filePath).delete();
      for (final album in ['a', 'b']) {
        final file = File('${dir.path}/music/$album/same.flac');
        await file.parent.create(recursive: true);
        await file.writeAsString('audio');
      }
      expect(await history.relocate('${dir.path}/music'), 0);
      expect((await history.list()).single.filePath, entry.filePath);
      expect(
        historyPathKeys('file:///sdcard/Music/Song.flac'),
        contains('/storage/emulated/0/Music/Song.flac'),
      );
      expect(
        historyPathKeys(
          'content://com.android.externalstorage.documents/document/primary%3AMusic%2FSong.flac',
        ),
        contains('/storage/emulated/0/Music/Song.flac'),
      );
      expect(
        historyPathKeys('/sdcard/Music/Song.flac'),
        isNot(contains('/sdcard/music/song.flac')),
      );
    },
  );
  test(
    'batch lookup spans bounded SQL chunks and skips stale newest rows',
    () async {
      final entry = await add('real', song);
      await history.upsert(
        HistoryEntry(
          id: 'stale',
          track: song,
          service: 'qobuz',
          filePath: '${dir.path}/missing.flac',
          downloadedAt: DateTime(2030),
        ),
      );
      final found = await history.findBatch(List.filled(130, song));
      expect(found, hasLength(130));
      expect(found.every((e) => e?.id == entry.id), isTrue);
    },
  );
  test(
    'backfill preserves real download metadata at the same physical path',
    () async {
      final entry = await add('download', song);
      final seed = HistoryEntry(
        id: 'scan',
        track: const Track(id: '', name: 'Inferred', artists: ''),
        service: 'library',
        filePath: entry.filePath,
        downloadedAt: DateTime(2020),
      );
      expect(await history.backfill(dir.path, [seed]), 0);
      expect((await history.list()).single.track.id, song.id);
    },
  );
  test(
    'relocation reuses scanned paths and persists its bounded cursor across reopen',
    () async {
      final first = await add('a', song);
      final second = await add(
        'b',
        const Track(
          id: 'b',
          name: 'Other',
          artists: 'Artist',
          albumName: 'Album',
        ),
      );
      final paths = <String>[];
      for (final entry in [first, second]) {
        final path = '${dir.path}/music/${entry.id}.flac';
        await Directory('${dir.path}/music').create(recursive: true);
        await File(entry.filePath).rename(path);
        paths.add(path);
      }
      expect(
        await history.relocate(
          '${dir.path}/music',
          limit: 1,
          scannedEntries: [
            scanned(paths[0]),
            scanned(paths[1], isrc: null, title: 'Other', album: 'Album'),
          ],
        ),
        1,
      );
      await history.close();
      history = HistoryDatabase(
        path: '${dir.path}/history.db',
        factory: databaseFactoryFfi,
      );
      expect(
        await history.relocate(
          '${dir.path}/music',
          limit: 1,
          scannedEntries: [
            scanned(paths[0]),
            scanned(paths[1], isrc: null, title: 'Other', album: 'Album'),
          ],
        ),
        1,
      );
      expect(
        (await history.list()).every((e) => paths.contains(e.filePath)),
        isTrue,
      );
    },
  );
  test(
    'bounded backfill is idempotent and removal stays removed on later scans',
    () async {
      final entries = <HistoryEntry>[];
      for (var i = 0; i < 3; i++) {
        final f = await File('${dir.path}/old$i.flac').writeAsString('audio');
        entries.add(
          HistoryEntry(
            id: 'scan$i',
            track: Track(id: '', name: 'Old$i', artists: 'Artist'),
            service: 'library',
            filePath: f.path,
            downloadedAt: DateTime(2020),
          ),
        );
      }
      expect(await history.backfill(dir.path, entries, limit: 2), 2);
      expect(await history.backfill(dir.path, entries, limit: 2), 1);
      await history.remove('scan0');
      expect(await history.backfill(dir.path, entries), 0);
      expect(await history.list(), hasLength(2));
    },
  );
}
