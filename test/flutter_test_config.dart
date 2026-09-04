import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const bool runningOnCi = bool.fromEnvironment('CI');

  // flutter_secure_storage has no plugin in the unit-test host, so any read/write
  // (e.g. the extension storage master key fetched in ExtensionsController.build)
  // would hang the test. Stub the channel: reads return empty, writes succeed —
  // enough for ExtensionMasterKey.loadOrCreate() to mint and "persist" a key.
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    switch (call.method) {
      case 'readAll':
        return <String, String>{};
      case 'containsKey':
        return false;
      default:
        // read / write / delete / deleteAll all resolve to null.
        return null;
    }
  });
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: const PlatformGoldensConfig(enabled: true),
      ciGoldensConfig: CiGoldensConfig(enabled: runningOnCi),
    ),
    run: testMain,
  );
}
