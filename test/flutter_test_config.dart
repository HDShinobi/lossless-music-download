import 'dart:async';

import 'package:alchemist/alchemist.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final runningOnCi = false; // set to true on CI via env var if needed
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: const PlatformGoldensConfig(enabled: true),
      ciGoldensConfig: CiGoldensConfig(enabled: runningOnCi),
    ),
    run: testMain,
  );
}
