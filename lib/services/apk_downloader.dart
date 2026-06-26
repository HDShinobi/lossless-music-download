import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads a release APK and hands it to the system package installer.
class ApkDownloader {
  /// Streams [url] to a file named after [version] in app-external storage,
  /// reporting progress via [onProgress] (received, total bytes; total is 0 if
  /// the server omits Content-Length). Returns the saved file path.
  ///
  /// Only HTTPS URLs are accepted.
  static Future<String> download(
    String url,
    String version, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!url.startsWith('https://')) {
      throw ArgumentError('Refusing to download a non-HTTPS APK URL');
    }
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final path = '${dir.path}/lossless-music-$version.apk';

    final resp = await http.Client().send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode != 200) {
      throw HttpException('APK download failed (HTTP ${resp.statusCode})');
    }
    final total = resp.contentLength ?? 0;
    final file = File(path);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    return path;
  }

  /// Opens [filePath] with the system installer (Android package installer).
  static Future<void> install(String filePath) async {
    await OpenFilex.open(filePath);
  }
}
