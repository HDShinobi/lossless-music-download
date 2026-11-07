import 'dart:collection';

import 'package:flutter/foundation.dart';

const _redacted = '[REDACTED]';
const _sensitiveKeyName =
    r'(?:[a-z0-9]+[_-])*(?:token|grant|state|key|secret|session|code|password|authorization)(?:[_-][a-z0-9]+)*';
final _sensitiveKey = RegExp('^$_sensitiveKeyName\$', caseSensitive: false);
const _candidateKeyName =
    r'[a-z0-9_-]*(?:token|grant|state|key|secret|session|code|password|authorization)[a-z0-9_-]*';
final _camelWordBoundary = RegExp(r'([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])');

bool _isSensitiveKey(String key) {
  if (_sensitiveKey.hasMatch(key)) return true;
  final words = key
      .replaceAllMapped(_camelWordBoundary, (match) {
        return '${match[1] ?? match[3]}_${match[2] ?? match[4]}';
      })
      .split(RegExp(r'[_-]'));
  // A trailing Code alone denotes diagnostics such as statusCode.
  return words.first.toLowerCase() == 'code' ||
      words.any(
        (word) => word.toLowerCase() != 'code' && _sensitiveKey.hasMatch(word),
      );
}

// Nested callback queries can occur outside http(s) URLs. Preserve their
// encoding and delimiters while replacing the sensitive values.
final _callbackValue = RegExp(
  r'((?:%(?:25)?(?:3f|26)|(?<![\w-]))'
  '($_candidateKeyName)'
  r'''(?:=|%(?:25)?3d))((?:Bearer|Basic)\s+[^\s,"';&]+|(?:(?!%(?:25)?26)[^&\s"'])+)''',
  caseSensitive: false,
);
final _url = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
final _queryValue = RegExp(r'([?&#]([^=?&#/]+)=)[^&#\s]*');
final _longUrlToken = RegExp(
  r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])',
);
final _bearer = RegExp(r'''\bBearer\s+[^\s,"';&]+''', caseSensitive: false);
final _keyValue = RegExp(
  r'''(["']?(?<![\w-])'''
  '($_candidateKeyName)'
  r'''["']?\s*[:=]\s*)((?:Bearer|Basic)\s+[^\s,"';&]+|\[REDACTED\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s&,;}\])]+)''',
  caseSensitive: false,
);
final _levelPrefix = RegExp(r'^\[(DEBUG|INFO|WARN|ERROR)\]\[([^\]]+)\] ?');
final _tagPrefix = RegExp(r'^\[([^\]]+)\] ?');
LogLevel? _consoleLevel;

/// Preserve the shim's console format while carrying its level to capturePrint.
void printAppLog(LogLevel level, String tag, String message) {
  final previousLevel = _consoleLevel;
  _consoleLevel = level;
  try {
    final prefix = level == LogLevel.info ? '' : '[${level.label}]';
    debugPrint('$prefix[$tag] $message');
  } finally {
    _consoleLevel = previousLevel;
  }
}

/// Sanitize at the storage boundary so both the viewer and clipboard are safe.
String redactLogText(String text) {
  var result = text.replaceAllMapped(
    _callbackValue,
    (match) => _isSensitiveKey(match[2]!) ? '${match[1]}$_redacted' : match[0]!,
  );
  result = result.replaceAllMapped(_url, (match) {
    final url = match[0]!.replaceAllMapped(_queryValue, (query) {
      var key = query[2]!;
      try {
        key = Uri.decodeQueryComponent(key);
      } on FormatException {
        // Malformed URLs can still contain plain sensitive keys.
      }
      return _isSensitiveKey(key) ? '${query[1]}$_redacted' : query[0]!;
    });
    final schemeEnd = url.indexOf('://') + 3;
    return url.substring(0, schemeEnd) +
        url.substring(schemeEnd).replaceAll(_longUrlToken, _redacted);
  });
  result = result.replaceAll(_bearer, 'Bearer $_redacted');
  return result.replaceAllMapped(
    _keyValue,
    (match) => _isSensitiveKey(match[2]!) ? '${match[1]}$_redacted' : match[0]!,
  );
}

enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARN'),
  error('ERROR');

  const LogLevel(this.label);
  final String label;
}

class LogEntry {
  const LogEntry(this.timestamp, this.level, this.tag, this.message);

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] [${level.label}] [$tag] $message';
}

class AppLog extends ChangeNotifier {
  static final instance = AppLog();
  static const maxEntries = 1000;
  static const _maxMessageLength = 8192;
  static const _truncation = '...[truncated]';
  final _entries = Queue<LogEntry>();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogLevel level, String tag, String message) {
    if (_entries.length == maxEntries) _entries.removeFirst();
    final sanitized = redactLogText(message);
    final storedMessage = sanitized.length <= _maxMessageLength
        ? sanitized
        : '${sanitized.substring(0, _maxMessageLength - _truncation.length)}$_truncation';
    _entries.add(
      LogEntry(DateTime.now(), level, redactLogText(tag), storedMessage),
    );
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void capturePrint(String message) {
    final prefix = _levelPrefix.firstMatch(message);
    if (prefix != null) {
      final level = LogLevel.values.firstWhere((l) => l.label == prefix[1]);
      add(level, prefix[2]!, message.substring(prefix.end));
      return;
    }
    final tag = _tagPrefix.firstMatch(message);
    add(
      _consoleLevel ?? LogLevel.debug,
      tag?[1] ?? 'Dart',
      tag == null ? message : message.substring(tag.end),
    );
  }
}

/// Install once at startup, retaining the console and existing crash policy.
void installAppLogHandlers(AppLog log) {
  final previousPrint = debugPrint;
  final previousFlutterError = FlutterError.onError;
  final previousPlatformError = PlatformDispatcher.instance.onError;
  var forwardingFlutterError = false;
  debugPrint = (message, {wrapWidth}) {
    if (message != null && !forwardingFlutterError) log.capturePrint(message);
    previousPrint(message, wrapWidth: wrapWidth);
  };
  FlutterError.onError = (details) {
    log.add(
      LogLevel.error,
      'Flutter',
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
    final wasForwarding = forwardingFlutterError;
    forwardingFlutterError = true;
    try {
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    } finally {
      forwardingFlutterError = wasForwarding;
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.add(LogLevel.error, 'Platform', '$error\n$stack');
    return previousPlatformError?.call(error, stack) ?? false;
  };
}
