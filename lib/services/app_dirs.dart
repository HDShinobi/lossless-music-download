import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppDirs {
  static Future<(String ext, String data)> extensionDirs() async {
    final base = await getApplicationSupportDirectory();
    return ('${base.path}/extensions', '${base.path}/ext_data');
  }

  static Future<String> downloadDir() async {
    final base =
        await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/LosslessMusic');
    await d.create(recursive: true);
    return d.path;
  }
}
