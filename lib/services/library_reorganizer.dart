import 'dart:io';
import 'dart:async';
import 'dart:convert';

import '../models/library_entry.dart';
import '../models/track.dart';
import 'download_paths.dart';
import 'download_templates.dart';
import 'history_database.dart';
import 'reenrich_orphans.dart';

enum ReorganizationStatus { ready, unchanged, conflict, missing, unsafe }

class ReorganizationSidecar {
  const ReorganizationSidecar(this.source, this.target, {this.shared = false});
  final String source, target;
  final bool shared;
}

class LibraryReorganizationItem {
  LibraryReorganizationItem(
    this.entry,
    this.target,
    this.status,
    this.sidecars,
  );
  final HistoryEntry entry;
  final String target;
  ReorganizationStatus status;
  final List<ReorganizationSidecar> sidecars;
  String get source => entry.filePath;
}

class LibraryReorganizationPlan {
  LibraryReorganizationPlan(this.root, this.items, this.physicalRoot);
  final String root, physicalRoot;
  final List<LibraryReorganizationItem> items;
  int get unchanged =>
      items.where((i) => i.status == ReorganizationStatus.unchanged).length;
  int get ready =>
      items.where((i) => i.status == ReorganizationStatus.ready).length;
}

class LibraryReorganizationResult {
  const LibraryReorganizationResult(
    this.moved,
    this.skipped,
    this.cancelled,
    this.errors,
  );
  final int moved, skipped;
  final bool cancelled;
  final Map<String, String> errors;
}

String _parent(String path) => File(path).parent.path;
String _stem(String path) => path.replaceFirst(RegExp(r'\.[^./]+$'), '');
bool _inside(String root, String path) => path.startsWith('$root/');
bool _traversal(String path) => path.split(RegExp(r'[/\\]')).contains('..');
Future<bool> _exists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

/// Reject links below the selected root, including dangling target links. The
/// root itself may use Android's /sdcard alias; its physical root is pinned.
Future<bool> _safe(String root, String path) async {
  if (!path.startsWith('/') ||
      _traversal(path) ||
      !_inside(root, path) ||
      isReEnrichTemporary(path)) {
    return false;
  }
  final physicalRoot = await Directory(root).resolveSymbolicLinks();
  var current = root;
  for (final segment in path.substring(root.length + 1).split('/')) {
    if (segment.isEmpty || segment == '.') return false;
    current = '$current/$segment';
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link) return false;
    if (type != FileSystemEntityType.notFound) {
      final physical = await File(current).resolveSymbolicLinks();
      if (!_inside(physicalRoot, physical)) return false;
    }
  }
  return true;
}

/// Only downloaded history rows authorize a move. Scan-only records never do.
class LibraryReorganizer {
  LibraryReorganizer(
    this.history, {
    Future<void> Function(String, String)? rename,
  }) : rename = rename ?? _rename;
  final HistoryDatabase history;
  final Future<void> Function(String, String) rename;
  static Future<void> _rename(String from, String to) async {
    await File(from).rename(to);
  }

  // Plan/apply and library loads share one queue, so replay cannot dismantle
  // a reservation while an active move is awaiting filesystem I/O.
  static final _pending = Expando<Future<void>>();
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _pending[history];
    final done = Completer<void>();
    _pending[history] = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<Map<String, String>> recover(String root) =>
      _exclusive(() => _recover(root.replaceFirst(RegExp(r'/+$'), '')));

  /// A bounded metadata lookup when there is nothing to recover. Never scan
  /// the library or infer ownership from a filename during journal replay.
  Future<Map<String, String>> _recover(String root) async {
    final db = await history.database;
    final rows = await db.query(
      'history_meta',
      where: "key LIKE 'reorganize:%'",
    );
    final errors = <String, String>{};
    for (final row in rows) {
      final intent = jsonDecode(row['value'] as String) as Map<String, dynamic>;
      if (intent['root'] != root) continue;
      final parts = (intent['parts'] as List).cast<Map<String, dynamic>>();
      var complete = true;
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        final source = part['source'] as String;
        final target = part['target'] as String;
        final size = part['size'] as int;
        try {
          if (!await _safe(root, source) || !await _safe(root, target)) {
            throw const FileSystemException('Unsafe recovery path');
          }
          final from = await File(source).stat();
          final to = await File(target).stat();
          final sourceFull =
              from.type == FileSystemEntityType.file &&
              size > 0 &&
              from.size == size;
          final targetFull =
              to.type == FileSystemEntityType.file &&
              size > 0 &&
              to.size == size;
          if (sourceFull &&
              to.type == FileSystemEntityType.file &&
              to.size == 0) {
            // The intent was persisted before our exclusive reservation.
            await File(target).delete();
          } else if (from.type == FileSystemEntityType.notFound && targetFull) {
            if (i == 0) {
              final id = intent['id'] as String;
              if (!await history.updateFilePath(id, source, target)) {
                final current = await db.query(
                  'history',
                  columns: ['file_path'],
                  where: 'id = ?',
                  whereArgs: [id],
                );
                if (current.isEmpty || current.single['file_path'] != target) {
                  throw StateError('History changed during recovery');
                }
              }
            }
          } else if (sourceFull && to.type == FileSystemEntityType.notFound) {
            // Killed before reservation, or rollback already restored source.
          } else if (sourceFull && targetFull && part['shared'] == true) {
            // Shared artwork intentionally keeps its source copy.
          } else {
            throw const FileSystemException('Unresolved move; files preserved');
          }
        } catch (e) {
          complete = false;
          errors[source] = '$e';
        }
      }
      if (complete) {
        await db.delete(
          'history_meta',
          where: 'key = ?',
          whereArgs: [row['key']],
        );
      }
    }
    return errors;
  }

  Future<LibraryReorganizationPlan> plan({
    required String root,
    required FolderOrganization mode,
    String filenameTemplate = '',
    String albumFolderTemplate = '',
    Set<String>? selection,
    List<LibraryEntry> tags = const [],
  }) => _exclusive(
    () => _plan(
      root: root,
      mode: mode,
      filenameTemplate: filenameTemplate,
      albumFolderTemplate: albumFolderTemplate,
      selection: selection,
      tags: tags,
    ),
  );

  Future<LibraryReorganizationPlan> _plan({
    required String root,
    required FolderOrganization mode,
    String filenameTemplate = '',
    String albumFolderTemplate = '',
    Set<String>? selection,
    List<LibraryEntry> tags = const [],
  }) async {
    if (!root.startsWith('/') ||
        _traversal(root) ||
        (filenameTemplate.isNotEmpty &&
            DownloadTemplates.validate(filenameTemplate) != null) ||
        (albumFolderTemplate.isNotEmpty &&
            DownloadTemplates.validate(albumFolderTemplate, folder: true) !=
                null)) {
      throw ArgumentError('Invalid download root or template');
    }
    root = root.replaceFirst(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw ArgumentError('Download root must not be filesystem root');
    }
    final recoveryErrors = await _recover(root);
    final items = <LibraryReorganizationItem>[];
    final tagByPath = {for (final tag in tags) tag.path: tag};
    for (var offset = 0; ; offset += 256) {
      final page = await history.list(limit: 256, offset: offset);
      for (final entry in page) {
        if (entry.service == 'library' ||
            entry.track.source == 'library_scan' ||
            entry.id.startsWith('scan:') ||
            isReEnrichTemporary(entry.filePath) ||
            (selection != null && !selection.contains(entry.filePath))) {
          continue;
        }
        final candidate = tagByPath[entry.filePath];
        final tag = candidate?.tagsFromFallback == false ? candidate : null;
        String? text(String? value) =>
            value?.trim().isNotEmpty == true ? value : null;
        final old = entry.track;
        // History owns identity and playlist position. Real tags supplement old
        // history rows whose original schema did not retain all template fields.
        final track = Track(
          id: old.id,
          source: old.source,
          name: text(tag?.title) ?? old.name,
          artists: text(tag?.artistName) ?? old.artists,
          albumName: text(tag?.albumName) ?? old.albumName,
          albumArtist: text(tag?.albumArtist) ?? old.albumArtist,
          trackNumber: tag?.trackNumber ?? old.trackNumber,
          discNumber: tag?.discNumber ?? old.discNumber,
          totalDiscs: tag?.totalDiscs ?? old.totalDiscs,
          releaseDate: text(tag?.releaseDate) ?? old.releaseDate,
          playlistPosition: old.playlistPosition,
          isrc: old.isrc ?? tag?.isrc,
        );
        final resolved = resolveDownloadTarget(
          root,
          track,
          mode: mode,
          filenameTemplate: filenameTemplate,
          albumFolderTemplate: albumFolderTemplate,
          quality: entry.quality,
        );
        final name = entry.filePath.split('/').last;
        final dot = name.lastIndexOf('.');
        final extension = dot < 0 ? '' : name.substring(dot);
        final target =
            '${resolved.dir}/${DownloadTemplates.preview(resolved.template, track, quality: entry.quality)}$extension';
        var status = ReorganizationStatus.ready;
        if (!await _safe(root, entry.filePath) || !await _safe(root, target)) {
          status = ReorganizationStatus.unsafe;
        } else if (!await File(entry.filePath).exists()) {
          if (entry.fileSize != null &&
              entry.fileSize! > 0 &&
              await File(target).exists() &&
              await File(target).length() == entry.fileSize &&
              await history.updateFilePath(entry.id, entry.filePath, target)) {
            status = ReorganizationStatus.unchanged;
          } else {
            status = ReorganizationStatus.missing;
          }
        } else if (entry.filePath == target) {
          status = ReorganizationStatus.unchanged;
        }
        if (recoveryErrors.containsKey(entry.filePath)) {
          status = ReorganizationStatus.conflict;
        }
        final sidecars = <ReorganizationSidecar>[];
        if (status == ReorganizationStatus.ready) {
          for (final ext in ['.lrc', '.jpg', '.jpeg', '.png', '.webp']) {
            final from = '${_stem(entry.filePath)}$ext';
            if (await _exists(from)) {
              sidecars.add(ReorganizationSidecar(from, '${_stem(target)}$ext'));
            }
          }
          if (_parent(entry.filePath) != _parent(target)) {
            for (final name in [
              'cover.jpg',
              'cover.jpeg',
              'cover.png',
              'folder.jpg',
              'folder.png',
            ]) {
              final from = '${_parent(entry.filePath)}/$name';
              if (await _exists(from) &&
                  !sidecars.any((s) => s.source == from)) {
                sidecars.add(
                  ReorganizationSidecar(
                    from,
                    '${_parent(target)}/$name',
                    shared: true,
                  ),
                );
              }
            }
          }
          for (final s in sidecars) {
            if (!await _safe(root, s.source) || !await _safe(root, s.target)) {
              status = ReorganizationStatus.unsafe;
            }
          }
        }
        items.add(LibraryReorganizationItem(entry, target, status, sidecars));
      }
      if (page.length < 256) break;
    }
    // Mark every participant in a collision; never choose a different filename
    // from the preview, or rely on another planned move vacating a target.
    final claims =
        <
          String,
          List<({LibraryReorganizationItem item, String source, bool shared})>
        >{};
    for (final item in items.where(
      (i) => i.status == ReorganizationStatus.ready,
    )) {
      for (final part in [
        ReorganizationSidecar(item.source, item.target),
        ...item.sidecars,
      ]) {
        claims.putIfAbsent(part.target.toLowerCase(), () => []).add((
          item: item,
          source: part.source,
          shared: part.shared,
        ));
        if (await _exists(part.target)) {
          item.status = ReorganizationStatus.conflict;
        }
      }
    }
    for (final owners in claims.values.where((v) => v.length > 1)) {
      final shared = owners.every(
        (o) => o.shared && o.source == owners.first.source,
      );
      if (!shared) {
        for (final owner in owners) {
          owner.item.status = ReorganizationStatus.conflict;
        }
      }
    }
    return LibraryReorganizationPlan(
      root,
      items,
      await Directory(root).resolveSymbolicLinks(),
    );
  }

  Future<LibraryReorganizationResult> apply(
    LibraryReorganizationPlan plan, {
    bool Function()? isCancelled,
    void Function(int done, LibraryReorganizationItem item)? onProgress,
  }) => _exclusive(
    () => _apply(plan, isCancelled: isCancelled, onProgress: onProgress),
  );

  Future<LibraryReorganizationResult> _apply(
    LibraryReorganizationPlan plan, {
    bool Function()? isCancelled,
    void Function(int done, LibraryReorganizationItem item)? onProgress,
  }) async {
    if (await Directory(plan.root).resolveSymbolicLinks() !=
        plan.physicalRoot) {
      throw const FileSystemException('Download root changed since preview');
    }
    final recoveryErrors = await _recover(plan.root);
    await cleanupReEnrichOrphans(plan.root);
    var moved = 0, skipped = 0, done = 0;
    var cancelled = false;
    final errors = <String, String>{...recoveryErrors};
    final sharedCopies = <String, String>{};
    final vacated = <String>{};
    for (final item in plan.items) {
      if (isCancelled?.call() == true) {
        cancelled = true;
        break;
      }
      if (item.status != ReorganizationStatus.ready ||
          recoveryErrors.containsKey(item.source)) {
        skipped++;
        continue;
      }
      final reserved = <String>[];
      final relocated = <ReorganizationSidecar>[];
      var recorded = false;
      var journaled = false;
      final journalKey = 'reorganize:${item.entry.id}';
      try {
        final bundle = [
          ReorganizationSidecar(item.source, item.target),
          ...item.sidecars,
        ];
        final parts = <Map<String, dynamic>>[];
        for (final part in bundle) {
          if (part.shared && sharedCopies[part.target] == part.source) continue;
          if (!await _safe(plan.root, part.source) ||
              !await _safe(plan.root, part.target) ||
              await _exists(part.target)) {
            throw const FileSystemException('Unsafe or occupied target');
          }
          final size = await File(part.source).length();
          if (size <= 0) throw const FileSystemException('Empty source');
          parts.add({
            'source': part.source,
            'target': part.target,
            'size': size,
            'shared': part.shared,
          });
        }
        final db = await history.database;
        await db.insert('history_meta', {
          'key': journalKey,
          'value': jsonEncode({
            'root': plan.root,
            'id': item.entry.id,
            'parts': parts,
          }),
        });
        journaled = true;
        for (final part in bundle) {
          if (!await _safe(plan.root, part.source) ||
              !await _safe(plan.root, part.target)) {
            throw const FileSystemException('Unsafe path');
          }
          if (part.shared && sharedCopies[part.target] == part.source) continue;
          await Directory(_parent(part.target)).create(recursive: true);
          // Exclusive reservation prevents rename/copy overwriting existing data,
          // including on Android 9 sdcardfs where hard links are unsupported.
          await File(part.target).create(exclusive: true);
          reserved.add(part.target);
        }
        for (final part in bundle) {
          if (part.shared && sharedCopies[part.target] == part.source) continue;
          if (part.shared) {
            await _copyVerified(part.source, part.target);
          } else {
            await _move(part.source, part.target);
          }
          relocated.add(part);
        }
        if (!await history.updateFilePath(
          item.entry.id,
          item.source,
          item.target,
        )) {
          throw StateError('History changed since preview');
        }
        recorded = true;
        await db.delete(
          'history_meta',
          where: 'key = ?',
          whereArgs: [journalKey],
        );
        for (final part in relocated.where((s) => s.shared)) {
          sharedCopies[part.target] = part.source;
        }
        vacated.add(_parent(item.source));
        moved++;
      } catch (e) {
        skipped++;
        errors[item.source] = '$e';
        // Roll back the bundle when persistence fails. If rollback itself fails,
        // retain its target copy rather than deleting the only surviving audio.
        if (!recorded) {
          for (final part in relocated.reversed) {
            try {
              if (part.shared) {
                await File(part.target).delete();
              } else if (!await _exists(part.source)) {
                await _move(part.target, part.source);
              }
              reserved.remove(part.target);
            } catch (_) {
              reserved.remove(part.target);
            }
          }
          for (final path in reserved) {
            try {
              if (await File(path).length() == 0) await File(path).delete();
            } on FileSystemException catch (_) {
              /* keep source */
            }
          }
        }
      }
      if (journaled && !recorded) {
        errors.addAll(await _recover(plan.root));
      }
      onProgress?.call(++done, item);
      await Future<void>.delayed(Duration.zero);
    }
    // Shared album covers remain with unselected audio. Remove the old cover
    // only when it is all that remains in a vacated folder.
    for (final source in sharedCopies.values.toSet()) {
      try {
        final remaining = await Directory(
          _parent(source),
        ).list(followLinks: false).toList();
        if (remaining.every((e) => sharedCopies.containsValue(e.path))) {
          await File(source).delete();
        }
      } on FileSystemException catch (_) {
        /* leave non-empty/inaccessible folders */
      }
    }
    for (final start in vacated) {
      var current = start;
      while (_inside(plan.root, current)) {
        try {
          if (!await _safe(plan.root, '$current/.cleanup') ||
              !await Directory(current).list(followLinks: false).isEmpty) {
            break;
          }
          await Directory(current).delete();
        } on FileSystemException catch (_) {
          break;
        }
        current = _parent(current);
      }
    }
    return LibraryReorganizationResult(moved, skipped, cancelled, errors);
  }

  Future<void> _copyVerified(String source, String target) async {
    final before = await File(source).stat();
    await File(source).copy(target);
    final after = await File(source).stat();
    if (before.size != await File(target).length() ||
        before.size != after.size ||
        before.modified != after.modified) {
      throw const FileSystemException('Copy verification failed');
    }
  }

  Future<void> _move(String source, String target) async {
    try {
      await rename(source, target);
    } on FileSystemException {
      await _copyVerified(source, target);
      await File(source).delete();
    }
  }
}
