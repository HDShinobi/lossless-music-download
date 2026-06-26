import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer release found on GitHub.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.apkUrl,
    required this.htmlUrl,
    required this.isPrerelease,
  });

  final String version;
  final String changelog;
  final String apkUrl;
  final String htmlUrl;
  final bool isPrerelease;
}

/// GitHub Releases "latest" endpoint for the public APK repo.
const _latestReleaseApi =
    'https://api.github.com/repos/HDShinobi/lossless-music-releases/releases/latest';

/// True if [latest] is a newer semantic version than [current]. Build suffixes
/// (`+n`) and prerelease tags (`-rc1`) are ignored; missing components are 0.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();

  final l = parse(latest);
  final c = parse(current);
  while (l.length < 3) {
    l.add(0);
  }
  while (c.length < 3) {
    c.add(0);
  }
  for (var i = 0; i < 3; i++) {
    if (l[i] != c[i]) return l[i] > c[i];
  }
  return false;
}

/// Parses a GitHub release JSON object into [UpdateInfo]. Returns null if the
/// release has no usable tag. The APK asset is the first asset whose name ends
/// in `.apk`; [UpdateInfo.apkUrl] is empty when none is attached.
UpdateInfo? parseLatestRelease(Map<String, dynamic> json) {
  final tag = (json['tag_name'] ?? '').toString();
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (version.isEmpty) return null;

  var apkUrl = '';
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is Map &&
          (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apkUrl = (a['browser_download_url'] ?? '').toString();
        break;
      }
    }
  }

  return UpdateInfo(
    version: version,
    changelog: (json['body'] ?? '').toString(),
    apkUrl: apkUrl,
    htmlUrl: (json['html_url'] ?? '').toString(),
    isPrerelease: (json['prerelease'] ?? false) == true,
  );
}

/// Checks GitHub for a newer release. Returns the [UpdateInfo] when a newer
/// version is available, otherwise null. Never throws — network/parse errors
/// resolve to null (with a debug log) so callers can fire-and-forget.
class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Overridable for tests; defaults to the running app's version.
  @visibleForTesting
  Future<String> Function()? currentVersionOverride;

  Future<String> _currentVersion() async {
    if (currentVersionOverride != null) return currentVersionOverride!();
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await _client.get(
        Uri.parse(_latestReleaseApi),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return null;

      final info = parseLatestRelease(json);
      if (info == null) return null;

      final current = await _currentVersion();
      return isNewerVersion(info.version, current) ? info : null;
    } catch (e) {
      debugPrint('[UpdateChecker] check failed: $e');
      return null;
    }
  }
}
