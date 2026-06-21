import 'package:path_provider/path_provider.dart';

class AppDirs {
  static Future<(String ext, String data)> extensionDirs() async {
    final base = await getApplicationSupportDirectory();
    return ('${base.path}/extensions', '${base.path}/ext_data');
  }
}
