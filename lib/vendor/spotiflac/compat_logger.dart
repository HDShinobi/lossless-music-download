// lib/vendor/spotiflac/compat_logger.dart
import 'package:flutter/foundation.dart';

/// Minimal logger shim so vendored SpotiFLAC services can use AppLogger without
/// the upstream dependency on package:spotiflac_android/utils/logger.dart.
class AppLogger {
  final String tag;
  const AppLogger(this.tag);
  void i(String message) => debugPrint('[$tag] $message');
  void e(String message) => debugPrint('[ERROR][$tag] $message');
}
