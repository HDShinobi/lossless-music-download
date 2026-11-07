import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/models/library_entry.dart';
import 'package:lossless_music_download/services/download_paths.dart';
import 'package:lossless_music_download/services/history_database.dart';
import 'package:lossless_music_download/services/library_reorganizer.dart';
import 'package:lossless_music_download/services/reenrich_orphans.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late HistoryDatabase db;
  late LibraryReorganizer service;
  Future<HistoryEntry> add(
    String name, {
    String title = 'Song',
    int disc = 1,
    int totalDiscs = 1,
    String source = 'qobuz',
  }) async {
    final file = File('${root.path}/old/$name.flac');
    await file.parent.create(recursive: true);
    await file.writeAsString('audio:$name');
    final entry = HistoryEntry(
      id: name,
      track: Track(
        id: 'qobuz:$name',
        source: source,
        name: title,
        artists: 'Artist',
        albumName: 'Album',
        discNumber: disc,
        totalDiscs: totalDiscs,
        trackNumber: 1,
        releaseDate: '2026-01-01',
        playlistPosition: 7,
      ),
      service: source,
      filePath: file.path,
      downloadedAt: DateTime(2026),
      fileSize: await file.length(),
    );
    await db.upsert(entry);
    return entry;
  }

  Future<LibraryReorganizationPlan> plan({
    Set<String>? selection,
    String filename = '{title}',
    String folder = '{artist}/{album}',
  }) => service.plan(
    root: root.path,
    mode: FolderOrganization.artistAlbum,
    filenameTemplate: filename,
    albumFolderTemplate: folder,
    selection: selection,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('c3_');
    db = HistoryDatabase(
      path: '${root.path}/history.db',
      factory: databaseFactoryFfi,
    );
    service = LibraryReorganizer(db);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'planner dry run uses persisted multidisc/date/playlist metadata',
    () async {
      final entry = await add('one', totalDiscs: 2);
      final p = await plan(
        filename: '{playlist_position}-{title}',
        folder: '{year}/{album}',
      );
      expect(p.items.single.target, '${root.path}/2026/Album/1-07-Song.flac');
      expect(await File(entry.filePath).exists(), isTrue);
      expect((await db.list()).single.track.totalDiscs, 2);
    },
  );
  test(
    'planner excludes scan history, unknown files, temp files and selection misses',
    () async {
      final a = await add('one');
      await add('two', title: 'Other');
      await add('scan', source: 'library_scan');
      await add('file.flac.reenrich-1762531200000000');
      await File('${root.path}/unknown.flac').writeAsString('user');
      expect((await plan(selection: {a.filePath})).items.length, 1);
      expect((await plan()).items.length, 2);
    },
  );
  test('planner reports duplicate targets and unchanged', () async {
    await add('one');
    await add('two');
    final p = await plan();
    expect(
      p.items.where((i) => i.status == ReorganizationStatus.conflict).length,
      2,
    );
    final unchanged = await plan(filename: '{id}', folder: 'old');
    expect(unchanged.unchanged, 2);
  });
  test(
    'planner rejects outside sources, traversal templates and symlink targets',
    () async {
      final entry = await add('one');
      await db.updateFilePath(
        entry.id,
        entry.filePath,
        '${root.path}/../outside.flac',
      );
      expect((await plan()).items.single.status, ReorganizationStatus.unsafe);
      await db.updateFilePath(
        entry.id,
        '${root.path}/../outside.flac',
        entry.filePath,
      );
      expect(() => plan(folder: '../escape'), throwsArgumentError);
      final outside = await Directory.systemTemp.createTemp('c3_out_');
      try {
        await Link('${root.path}/Artist').create(outside.path);
        expect((await plan()).items.single.status, ReorganizationStatus.unsafe);
      } finally {
        await outside.delete();
      }
    },
  );
  test(
    'executor moves lyrics and track cover, updates history, cleans empty dirs, reruns',
    () async {
      final entry = await add('one');
      await File(
        entry.filePath.replaceAll('.flac', '.lrc'),
      ).writeAsString('lyrics');
      await File(
        entry.filePath.replaceAll('.flac', '.jpg'),
      ).writeAsString('cover');
      final p = await plan();
      final result = await service.apply(p);
      expect(result.moved, 1);
      final target = p.items.single.target;
      expect(await File(target).readAsString(), 'audio:one');
      expect(
        await File(target.replaceAll('.flac', '.lrc')).readAsString(),
        'lyrics',
      );
      expect(
        await File(target.replaceAll('.flac', '.jpg')).readAsString(),
        'cover',
      );
      expect((await db.list()).single.filePath, target);
      expect(await Directory('${root.path}/old').exists(), isFalse);
      expect((await plan()).unchanged, 1);
      expect((await service.apply(p)).moved, 0);
    },
  );
  test('executor never overwrites a late audio or sidecar conflict', () async {
    final entry = await add('one');
    await File(
      entry.filePath.replaceAll('.flac', '.lrc'),
    ).writeAsString('lyrics');
    final p = await plan();
    final target = File(p.items.single.target.replaceAll('.flac', '.lrc'));
    await target.parent.create(recursive: true);
    await target.writeAsString('someone else');
    expect((await service.apply(p)).skipped, 1);
    expect(await File(entry.filePath).exists(), isTrue);
    expect(await target.readAsString(), 'someone else');
    expect((await db.list()).single.filePath, entry.filePath);
  });
  test('executor revalidates symlinks after preview', () async {
    final entry = await add('one');
    final p = await plan();
    final outside = await Directory.systemTemp.createTemp('c3_out_');
    try {
      await Link('${root.path}/Artist').create(outside.path);
      expect((await service.apply(p)).skipped, 1);
      expect(await File(entry.filePath).exists(), isTrue);
      expect(await outside.list().isEmpty, isTrue);
    } finally {
      await outside.delete();
    }
  });
  test(
    'copy fallback verifies size and preserves source on history CAS failure',
    () async {
      final entry = await add('one');
      service = LibraryReorganizer(
        db,
        rename: (_, _) async => throw const FileSystemException('EXDEV'),
      );
      final p = await plan();
      expect((await service.apply(p)).moved, 1);
      expect(await File(p.items.single.target).readAsString(), 'audio:one');
      expect(await File(entry.filePath).exists(), isFalse);
      final second = await add('two', title: 'Other');
      final pending = await plan();
      await db.updateFilePath(
        second.id,
        second.filePath,
        '${root.path}/elsewhere.flac',
      );
      expect((await service.apply(pending)).moved, 0);
      expect(await File(second.filePath).exists(), isTrue);
    },
  );
  test('cancellation stops between tracks and reports progress', () async {
    await add('one');
    await add('two', title: 'Other');
    var done = 0;
    final result = await service.apply(
      await plan(),
      isCancelled: () => done == 1,
      onProgress: (current, _) => done = current,
    );
    expect(result.moved, 1);
    expect(result.cancelled, isTrue);
  });
  test(
    'shared album cover follows selected files but stays with unselected audio',
    () async {
      final one = await add('one');
      final two = await add('two', title: 'Other');
      final cover = await File(
        '${root.path}/old/cover.jpg',
      ).writeAsString('cover');
      expect(
        (await service.apply(await plan(selection: {one.filePath}))).moved,
        1,
      );
      expect(await cover.exists(), isTrue);
      expect(
        await File('${root.path}/Artist/Album/cover.jpg').readAsString(),
        'cover',
      );
      // A pre-existing cover is a conflict, even though the audio target is free.
      expect(
        (await plan(selection: {two.filePath})).items.single.status,
        ReorganizationStatus.conflict,
      );
    },
  );
  test(
    'shared covers across a whole album do not create false audio conflicts',
    () async {
      await add('one');
      await add('two', title: 'Other');
      await File('${root.path}/old/cover.jpg').writeAsString('cover');
      final p = await plan();
      expect(p.ready, 2);
      expect((await service.apply(p)).moved, 2);
      expect(await Directory('${root.path}/old').exists(), isFalse);
    },
  );
  test(
    'duplicate audio targets still conflict when they also share a cover',
    () async {
      await add('one');
      await add('two');
      await File('${root.path}/old/cover.jpg').writeAsString('cover');
      expect((await plan()).ready, 0);
    },
  );
  test('late audio conflicts never overwrite the destination', () async {
    final one = await add('one');
    final p = await plan();
    final target = File(p.items.single.target);
    await target.parent.create(recursive: true);
    await target.writeAsString('user audio');
    expect((await service.apply(p)).skipped, 1);
    expect(await target.readAsString(), 'user audio');
    expect(await File(one.filePath).exists(), isTrue);
  });
  test('partial bundle failure rolls back already moved audio', () async {
    final one = await add('one');
    final lyrics = await File(
      one.filePath.replaceAll('.flac', '.lrc'),
    ).writeAsString('lyrics');
    final p = await plan();
    await lyrics.delete();
    final result = await service.apply(p);
    expect(result.moved, 0);
    expect(result.errors, isNotEmpty);
    expect(await File(one.filePath).readAsString(), 'audio:one');
    expect(await File(p.items.single.target).exists(), isFalse);
    expect((await db.list()).single.filePath, one.filePath);
  });
  test('real tags supplement old history metadata for templates', () async {
    final one = await add('one');
    final p = await service.plan(
      root: root.path,
      mode: FolderOrganization.artistAlbum,
      filenameTemplate: '{title}',
      albumFolderTemplate: '{year}/{album}',
      tags: [
        LibraryEntry(
          path: one.filePath,
          name: 'one.flac',
          sizeBytes: 5,
          format: 'FLAC',
          verified: true,
          title: 'Edited',
          totalDiscs: 2,
          discNumber: 1,
          releaseDate: '2025-01-01',
        ),
      ],
    );
    expect(p.items.single.target, '${root.path}/2025/Album/1-Edited.flac');
  });
  test('filesystem root cannot be used as a download root', () async {
    expect(
      () => service.plan(root: '/', mode: FolderOrganization.none),
      throwsArgumentError,
    );
  });
  test(
    'orphan cleanup ignores fresh temps, deletes only stale matching files',
    () async {
      await File('${root.path}/x.flac').writeAsString('original');
      final stale = File('${root.path}/x.flac.reenrich-1762531200000000.flac');
      final fresh = File('${root.path}/x.flac.reenrich-1762531200000001.flac');
      final normal = File('${root.path}/reenrich-song.flac');
      for (final f in [stale, fresh, normal]) {
        await f.writeAsString('x');
      }
      await stale.setLastModified(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );
      await cleanupReEnrichOrphans(root.path);
      expect(isReEnrichTemporary(fresh.path), isTrue);
      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(await normal.exists(), isTrue);
    },
  );
  for (final stage in [
    'intent',
    'reserved',
    'moved',
    'recorded',
    'both',
    'wrong',
  ]) {
    test('replays crash after $stage without losing audio', () async {
      final entry = await add('one');
      final target = File((await plan()).items.single.target);
      await target.parent.create(recursive: true);
      await (await db.database).insert('history_meta', {
        'key': 'reorganize:${entry.id}',
        'value': jsonEncode({
          'root': root.path,
          'id': entry.id,
          'parts': [
            {
              'source': entry.filePath,
              'target': target.path,
              'size': await File(entry.filePath).length(),
              'shared': false,
            },
          ],
        }),
      });
      if (stage == 'reserved') await target.create();
      if (['moved', 'recorded'].contains(stage)) {
        await File(entry.filePath).rename(target.path);
      }
      if (stage == 'recorded') {
        await db.updateFilePath(entry.id, entry.filePath, target.path);
      }
      if (stage == 'both') await File(entry.filePath).copy(target.path);
      if (stage == 'wrong') await target.writeAsString('partial');
      await db.close();
      final p = await plan();
      if (['moved', 'recorded'].contains(stage)) {
        expect((await db.list()).single.filePath, target.path);
        expect(p.unchanged, 1);
      } else {
        expect((await db.list()).single.filePath, entry.filePath);
        expect(await File(entry.filePath).readAsString(), 'audio:one');
        expect(await target.exists(), ['both', 'wrong'].contains(stage));
        expect(
          p.items.single.status,
          ['both', 'wrong'].contains(stage)
              ? ReorganizationStatus.conflict
              : ReorganizationStatus.ready,
        );
      }
      final intents = await (await db.database).query(
        'history_meta',
        where: "key LIKE 'reorganize:%'",
      );
      expect(intents.isEmpty, !['both', 'wrong'].contains(stage));
    });
  }
  test('apply persists audio and sidecar intents before rename', () async {
    final entry = await add('one');
    await File(
      entry.filePath.replaceAll('.flac', '.lrc'),
    ).writeAsString('lyrics');
    var checked = false;
    service = LibraryReorganizer(
      db,
      rename: (from, to) async {
        final rows = await (await db.database).query(
          'history_meta',
          where: "key LIKE 'reorganize:%'",
        );
        expect(rows, hasLength(1));
        final intent = jsonDecode(rows.single['value'] as String) as Map;
        expect(intent['parts'], hasLength(2));
        checked = true;
        await File(from).rename(to);
      },
    );
    expect((await service.apply(await plan())).moved, 1);
    expect(checked, isTrue);
    expect(
      await (await db.database).query(
        'history_meta',
        where: "key LIKE 'reorganize:%'",
      ),
      isEmpty,
    );
  });
  test(
    'missing history relinks only a target with matching recorded size',
    () async {
      final entry = await add('one');
      final target = File((await plan()).items.single.target);
      await target.parent.create(recursive: true);
      await File(entry.filePath).rename(target.path);
      expect((await plan()).unchanged, 1);
      expect((await db.list()).single.filePath, target.path);
    },
  );
  test(
    'orphan cleanup preserves user filenames and temps without originals',
    () async {
      for (final name in [
        'x.reenrich-1.flac',
        'x.flac.reenrich-123.flac',
        'x.flac.reenrich-1762531200000000.mp3',
        'absent.flac.reenrich-1762531200000000.flac',
      ]) {
        final file = await File('${root.path}/$name').writeAsString('user');
        await file.setLastModified(DateTime(2020));
        await cleanupReEnrichOrphans(root.path);
        expect(await file.exists(), isTrue, reason: name);
      }
    },
  );
  test(
    'library recovery waits for an active move on the same database',
    () async {
      await add('one');
      final entered = Completer<void>();
      final proceed = Completer<void>();
      service = LibraryReorganizer(
        db,
        rename: (from, to) async {
          entered.complete();
          await proceed.future;
          final rows = await (await db.database).query(
            'history_meta',
            where: "key LIKE 'reorganize:%'",
          );
          expect(rows, hasLength(1));
          await File(from).rename(to);
        },
      );
      final applying = service.apply(await plan());
      await entered.future;
      final recovering = LibraryReorganizer(db).recover(root.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      proceed.complete();
      expect((await applying).moved, 1);
      expect(await recovering, isEmpty);
    },
  );
  test('apply replays a reservation left since preview', () async {
    final entry = await add('one');
    final p = await plan();
    final target = File(p.items.single.target);
    await target.parent.create(recursive: true);
    await target.create();
    await (await db.database).insert('history_meta', {
      'key': 'reorganize:${entry.id}',
      'value': jsonEncode({
        'root': root.path,
        'id': entry.id,
        'parts': [
          {
            'source': entry.filePath,
            'target': target.path,
            'size': await File(entry.filePath).length(),
            'shared': false,
          },
        ],
      }),
    });
    expect((await service.apply(p)).moved, 1);
    expect(await target.readAsString(), 'audio:one');
  });
}
