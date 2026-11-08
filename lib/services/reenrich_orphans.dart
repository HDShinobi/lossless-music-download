import 'dart:io';

final _temporary = RegExp(r'^(.+\.([^.\/]+))\.reenrich-[0-9]{16}\.([^.\/]+)$');

String? _original(String path) {
  final match = _temporary.firstMatch(path);
  if (match == null || match[2]!.toLowerCase() != match[3]) return null;
  return match[1];
}

bool isReEnrichTemporary(String path) => _original(path) != null;

/// Never follow links or delete fresh output belonging to an active tag write.
Future<void> cleanupReEnrichOrphans(
  String root, {
  Iterable<String>? candidates,
  Duration minimumAge = const Duration(minutes: 5),
}) async {
  final cutoff = DateTime.now().subtract(minimumAge);
  try {
    final entities = candidates == null
        ? Directory(root).list(recursive: true, followLinks: false)
        : Stream<FileSystemEntity>.fromIterable(
            candidates
                .where(
                  (path) =>
                      path.startsWith('$root/') && isReEnrichTemporary(path),
                )
                .map(File.new),
          );
    await for (final entity in entities) {
      if (entity is! File || !isReEnrichTemporary(entity.path)) continue;
      try {
        if (await FileSystemEntity.type(entity.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await FileSystemEntity.type(
                  _original(entity.path)!,
                  followLinks: false,
                ) ==
                FileSystemEntityType.file &&
            (await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException catch (_) {
        // A concurrent writer/removal or revoked permission can be retried later.
      }
    }
  } on FileSystemException catch (_) {
    // Scanning remains usable when a subtree is inaccessible.
  }
}
