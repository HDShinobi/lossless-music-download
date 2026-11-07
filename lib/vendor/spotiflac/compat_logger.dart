// lib/vendor/spotiflac/compat_logger.dart
import '../../services/app_log.dart';

/// Minimal logger shim so vendored SpotiFLAC services can use AppLogger without
/// the upstream dependency on package:spotiflac_android/utils/logger.dart.
class AppLogger {
  final String tag;
  const AppLogger(this.tag);
  void d(String message) => printAppLog(LogLevel.debug, tag, message);
  void i(String message) => printAppLog(LogLevel.info, tag, message);
  void w(String message) => printAppLog(LogLevel.warning, tag, message);
  void e(String message) => printAppLog(LogLevel.error, tag, message);
}
