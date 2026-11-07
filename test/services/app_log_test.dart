import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/app_log.dart';
import 'package:lossless_music_download/vendor/spotiflac/compat_logger.dart';

void main() {
  test('keeps the last 1000 entries in chronological order', () {
    final log = AppLog();
    for (var i = 0; i < 1002; i++) {
      log.add(LogLevel.info, 'Test', 'entry $i');
    }
    expect(log.entries, hasLength(1000));
    expect(log.entries.first.message, 'entry 2');
    expect(log.entries.last.message, 'entry 1001');
    expect(log.entries.last.timestamp, isA<DateTime>());
    expect(log.entries.last.toString(), contains('[INFO] [Test] entry 1001'));
    expect(() => log.entries.clear(), throwsUnsupportedError);
    log.clear();
    expect(log.entries, isEmpty);
  });

  for (final key in [
    'token',
    'grant',
    'state',
    'key',
    'secret',
    'session',
    'code',
    'password',
    'authorization',
    'access_token',
    'client_secret',
    'api_key',
    'session_id',
    'api-key',
    'x-api-key',
  ]) {
    test('redacts mixed-case $key query and text values before storage', () {
      final log = AppLog();
      log.add(
        LogLevel.info,
        'Test',
        'https://host/path?${key.toUpperCase()}=sensitive&safe=ok '
            '"$key": "another secret"',
      );
      final text = log.entries.single.message;
      expect(text, isNot(contains('sensitive')));
      expect(text, isNot(contains('another secret')));
      expect(text, contains('&safe=ok'));
      expect(text, contains('[REDACTED]'));
    });
  }

  for (final key in [
    'sessionId',
    'SessionId',
    'sessionSecret',
    'accessToken',
    'AccessToken',
    'refreshToken',
    'apiKey',
    'APIKey',
    'authToken',
    'clientSecret',
    'grantCode',
    'sessionCount',
  ]) {
    test('redacts compound $key in JSON, assignments, and fields', () {
      final raw =
          '{"session_secret":"x","$key":"SECRETid"} '
          '$key=SECRETid $key: SECRETid '
          'https://host/path?$key=SECRETid&safe=ok';
      final redacted = redactLogText(raw);
      expect(
        redacted,
        '{"session_secret":[REDACTED],"$key":[REDACTED]} '
        '$key=[REDACTED] $key: [REDACTED] '
        'https://host/path?$key=[REDACTED]&safe=ok',
      );
      expect(redactLogText(redacted), redacted);
    });
  }

  for (final key in [
    'statusCode',
    'StatusCode',
    'keyboard',
    'stateful',
    'stateless',
    'codec',
    'keyframe',
  ]) {
    test('preserves unrelated $key in JSON, assignments, and fields', () {
      final raw =
          '{"$key":"visible"} $key=visible $key: visible '
          'https://host/path?$key=visible&safe=ok';
      expect(redactLogText(raw), raw);
    });
  }

  test('redacts encoded query keys, bearer values, and long URL tokens', () {
    final log = AppLog();
    log.add(
      LogLevel.error,
      'token=tag-secret',
      'https://host/path?%74oken=encoded-secret&safe=ok '
          'Authorization: Bearer short-secret '
          'https://host/abcdef0123456789abcdef0123456789?value='
          'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789%2B%2F%3D '
          'outside-01234567890123456789012345678901',
    );
    final entry = log.entries.single;
    expect(entry.tag, isNot(contains('tag-secret')));
    expect(entry.message, isNot(contains('encoded-secret')));
    expect(entry.message, isNot(contains('short-secret')));
    expect(entry.message, isNot(contains('abcdef0123456789')));
    expect(entry.message, isNot(contains('AbCdEfGh')));
    expect(entry.message, contains('outside-01234567890123456789012345678901'));
    expect(entry.message, contains('&safe=ok'));
  });

  test('redaction is stable and removes complete authorization values', () {
    const raw =
        'https://host/path?token=private&safe=ok '
        'Authorization: Basic c2VjcmV0 '
        'Authorization: Bearer short-secret';
    final redacted = redactLogText(raw);
    expect(
      redacted,
      'https://host/path?token=[REDACTED]&safe=ok '
      'Authorization: [REDACTED] Authorization: [REDACTED]',
    );
    expect(redactLogText(redacted), redacted);
  });

  test('redacts the exact bare encoded callback from review', () {
    expect(
      redactLogText(
        'cb=spotiflac%3A%2F%2Fsession-grant%3Fstate%3Dabc123%26grant%3Dgr_abc',
      ),
      'cb=spotiflac%3A%2F%2Fsession-grant%3Fstate%3D[REDACTED]%26grant%3D[REDACTED]',
    );
    expect(
      redactLogText(
        'cb=spotiflac%253A%252F%252Fsession-grant%253Fstate%253Dabc123%2526grant%253Dgr_abc',
      ),
      'cb=spotiflac%253A%252F%252Fsession-grant%253Fstate%253D[REDACTED]%2526grant%253D[REDACTED]',
    );
  });

  for (final separator in ['%3D', '%3d', '%253D', '=']) {
    for (final wrapper in ['bare', 'sentence', 'url']) {
      test('redacts $separator callback values in $wrapper', () {
        final callback =
            'cb=spotiflac%3A%2F%2Fsession-grant%3Fstate${separator}abc123'
            '%26grant${separator}gr_abc%26safe${separator}ok';
        final raw = switch (wrapper) {
          'sentence' => 'Received "$callback" done',
          'url' => 'https://api.zarz.moe/v2/challenge?$callback&mode=login',
          _ => callback,
        };
        final redacted = redactLogText(raw);
        expect(redacted, isNot(contains('abc123')));
        expect(redacted, isNot(contains('gr_abc')));
        expect(redacted, contains('state$separator[REDACTED]'));
        expect(redacted, contains('grant$separator[REDACTED]'));
        expect(redacted, contains('%26safe${separator}ok'));
        expect(redactLogText(redacted), redacted);
      });
    }
  }

  test('encoded values stop at delimiters without swallowing context', () {
    const raw =
        'state%3Done%26safe=ok grant%253Dtwo%2526safe=ok '
        'token%3Dthree&safe=ok secret%3Dfour end '
        'key%3Dfive" next session%3Dsix\' last';
    expect(
      redactLogText(raw),
      'state%3D[REDACTED]%26safe=ok grant%253D[REDACTED]%2526safe=ok '
      'token%3D[REDACTED]&safe=ok secret%3D[REDACTED] end '
      'key%3D[REDACTED]" next session%3D[REDACTED]\' last',
    );
  });

  test('preserves unrelated key names in text and URLs', () {
    const raw =
        'statusCode: 404 keyboard=visible stateful=true '
        'https://x.com/a?statusCode=404&keyboard=visible&stateful=true';
    expect(redactLogText(raw), raw);
  });

  test('long URL tokens preserve the host and path separators', () {
    const raw =
        'https://x.com/a/abcdef0123456789abcdef0123456789/end '
        'https://x.com/b/AbCdEfGhIjKlMnOpQrStUvWxYz_0123456789-/end';
    expect(
      redactLogText(raw),
      'https://x.com/a/[REDACTED]/end https://x.com/b/[REDACTED]/end',
    );
  });

  test('bounds stored messages after redaction and marks truncation', () {
    final log = AppLog();
    final longMessage = 'token=private ${'x' * 9000} tail';
    log.add(LogLevel.info, 'Test', longMessage);
    final stored = log.entries.single.message;
    expect(stored.length, lessThanOrEqualTo(8192));
    expect(stored, startsWith('token=[REDACTED] '));
    expect(stored, endsWith('[truncated]'));
    expect(stored, isNot(contains('tail')));
    log.add(LogLevel.info, 'Test', 'small');
    expect(log.entries.last.message, 'small');
  });

  for (final throwsAfterForwarding in [false, true]) {
    test(
      'stores Flutter errors once; forwarding throws=$throwsAfterForwarding',
      () {
        final previous = debugPrint;
        final previousFlutter = FlutterError.onError;
        final previousPlatform = PlatformDispatcher.instance.onError;
        final previousPresent = FlutterError.presentError;
        final log = AppLog();
        final console = <String?>[];
        debugPrint = (message, {wrapWidth}) => console.add(message);
        FlutterError.presentError = (details) {
          debugPrint('Flutter console: ${details.exceptionAsString()}');
          if (throwsAfterForwarding) throw StateError('forwarding failed');
        };
        FlutterError.onError = FlutterError.presentError;
        try {
          installAppLogHandlers(log);
          final details = FlutterErrorDetails(exception: Exception('failure'));
          if (throwsAfterForwarding) {
            expect(() => FlutterError.onError!(details), throwsStateError);
          } else {
            FlutterError.onError!(details);
          }
          expect(log.entries, hasLength(1));
          expect(log.entries.single.level, LogLevel.error);
          expect(console, ['Flutter console: Exception: failure']);
          debugPrint('after error');
          expect(log.entries.last.message, 'after error');
          expect(log.entries.last.level, LogLevel.debug);
        } finally {
          debugPrint = previous;
          FlutterError.onError = previousFlutter;
          PlatformDispatcher.instance.onError = previousPlatform;
          FlutterError.presentError = previousPresent;
        }
      },
    );
  }

  test('captures debugPrint and logger levels while forwarding console', () {
    final previous = debugPrint;
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    final console = <String?>[];
    final log = AppLog();
    debugPrint = (message, {wrapWidth}) => console.add(message);
    try {
      installAppLogHandlers(log);
      debugPrint('[DownloadQueue] started');
      const logger = AppLogger('ShareIntent');
      logger.d('debug');
      logger.i('info');
      logger.w('warning');
      logger.e('error');
      expect(log.entries.map((e) => e.level), [
        LogLevel.debug,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]);
      expect(log.entries.first.tag, 'DownloadQueue');
      expect(log.entries.last.tag, 'ShareIntent');
      expect(console, [
        '[DownloadQueue] started',
        '[DEBUG][ShareIntent] debug',
        '[ShareIntent] info',
        '[WARN][ShareIntent] warning',
        '[ERROR][ShareIntent] error',
      ]);
    } finally {
      debugPrint = previous;
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    }
  });

  test(
    'records errors and preserves previous handlers and unhandled result',
    () {
      final previous = debugPrint;
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final log = AppLog();
      FlutterErrorDetails? forwarded;
      Object? forwardedError;
      StackTrace? forwardedStack;
      FlutterError.onError = (details) => forwarded = details;
      PlatformDispatcher.instance.onError = (error, stack) {
        forwardedError = error;
        forwardedStack = stack;
        return true;
      };
      try {
        installAppLogHandlers(log);
        final details = FlutterErrorDetails(
          exception: Exception('token=private'),
        );
        FlutterError.onError!(details);
        expect(forwarded, same(details));
        final error = StateError('failure');
        final stack = StackTrace.current;
        expect(PlatformDispatcher.instance.onError!(error, stack), isTrue);
        expect(forwardedError, same(error));
        expect(forwardedStack, same(stack));
        expect(log.entries.every((e) => e.level == LogLevel.error), isTrue);
        expect(log.entries.first.message, isNot(contains('private')));
        PlatformDispatcher.instance.onError = null;
        installAppLogHandlers(AppLog());
        expect(PlatformDispatcher.instance.onError!(error, stack), isFalse);
      } finally {
        debugPrint = previous;
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    },
  );
}
