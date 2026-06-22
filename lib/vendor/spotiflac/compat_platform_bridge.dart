// Compat shim: PlatformBridge stub for direct file paths (no content:// URIs).
// Upstream calls safStat only for content:// URIs; we pass direct paths.
import 'dart:io';

class PlatformBridge {
  static Future<Map<String, dynamic>> safStat(String uri) async =>
      {'size': await File(uri).length()};

  static Future<String?> copyContentUriToTemp(String uri) async => null;
}
