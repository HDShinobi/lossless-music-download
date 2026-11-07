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
  Duration minimumAge = const Duration(minutes: 5),
}) async {
  final cutoff = DateTime.now().subtract(minimumAge);
  try {
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File || !isReEnrichTemporary(entity.path)) continue;
      try {
        if (await FileSystemEntity.type(
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
