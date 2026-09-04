import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Loads (or creates) the base64-encoded 32-byte master key that the Go engine
/// uses to encrypt extension settings/credentials at rest (introduced in the
/// SpotiFLAC v4.9.5 sync). The key lives only in the Android Keystore via
/// flutter_secure_storage — the Go side never persists it.
///
/// This MUST be handed to the backend (SetExtensionStorageMasterKey) BEFORE
/// InitExtensionSystem: otherwise the engine refuses to configure the extension
/// directories and every install/upgrade fails with "extension directory is not
/// configured" while no extensions load. Key name matches upstream so a future
/// shared key stays compatible.
class ExtensionMasterKey {
  ExtensionMasterKey._();

  static const _keyName = 'extension_storage_master_key_v2';
  static const FlutterSecureStorage _store = FlutterSecureStorage();

  static Future<String> loadOrCreate() async {
    final existing = await _store.read(key: _keyName);
    if (existing != null) {
      try {
        if (base64Decode(existing).length == 32) return existing;
      } on FormatException {
        // Malformed legacy value — replace with a fresh keystore-backed key.
      }
    }

    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    final encoded = base64Encode(key);
    await _store.write(key: _keyName, value: encoded);
    return encoded;
  }
}
