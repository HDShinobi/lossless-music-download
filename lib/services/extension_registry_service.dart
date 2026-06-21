import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/store_extension.dart';

class ExtensionRegistryService {
  ExtensionRegistryService(this._client);
  final http.Client _client;

  /// Fetch aggregator -> each registry -> merged catalog (dedup by id, first wins).
  Future<List<StoreExtension>> fetchCatalog(String aggregatorUrl) async {
    final aggRes = await _client.get(Uri.parse(aggregatorUrl));
    if (aggRes.statusCode != 200) throw HttpException('aggregator ${aggRes.statusCode}');
    final agg = jsonDecode(aggRes.body) as Map<String, dynamic>;
    final repos = (agg['repos'] as List? ?? []);
    final byId = <String, StoreExtension>{};
    for (final r in repos) {
      final repo = Map<String, dynamic>.from(r as Map);
      final url = (repo['url'] ?? '').toString();
      final name = (repo['name'] ?? url).toString();
      if (url.isEmpty) continue;
      try {
        final regRes = await _client.get(Uri.parse(url));
        if (regRes.statusCode != 200) continue;
        final reg = jsonDecode(regRes.body) as Map<String, dynamic>;
        for (final e in (reg['extensions'] as List? ?? [])) {
          final se = StoreExtension.fromRegistryJson(
            Map<String, dynamic>.from(e as Map),
            name,
          );
          byId.putIfAbsent(se.id, () => se);
        }
      } catch (_) {
        // skip a dead/invalid registry, keep others
      }
    }
    return byId.values.toList();
  }

  /// Download the .spotiflac-ext to destDir/[id].spotiflac-ext; returns the file path.
  Future<String> downloadExtension(StoreExtension e, String destDir) async {
    final safeId = e.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    if (safeId.isEmpty || safeId == '.' || safeId == '..') {
      throw ArgumentError('invalid extension id: ${e.id}');
    }
    final res = await _client.get(Uri.parse(e.downloadUrl));
    if (res.statusCode != 200) throw HttpException('download ${res.statusCode}');
    final dir = Directory(destDir)..createSync(recursive: true);
    final path = '${dir.path}/$safeId.spotiflac-ext';
    File(path).writeAsBytesSync(res.bodyBytes);
    return path;
  }
}
