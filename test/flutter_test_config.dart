import 'dart:async';

import 'package:alchemist/alchemist.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const bool runningOnCi = bool.fromEnvironment('CI');
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: const PlatformGoldensConfig(enabled: true),
      ciGoldensConfig: CiGoldensConfig(enabled: runningOnCi),
    ),
    run: testMain,
  );
}
