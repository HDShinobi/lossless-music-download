import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';

void main() {
  group('isRateLimitError', () {
    test('matches the real device error string', () {
      expect(
        isRateLimitError(
            'All providers failed. Last error: HTTP 429 for https://api.zarz.moe/v2/media'),
        isTrue,
      );
    });

    test('matches the various rate-limit phrasings', () {
      expect(isRateLimitError('rate limit exceeded'), isTrue);
      expect(isRateLimitError('error_type: rate_limit'), isTrue);
      expect(isRateLimitError('Too Many Requests'), isTrue);
      expect(isRateLimitError('status 429'), isTrue);
    });

    test('does not match unrelated errors or unrelated numbers', () {
      expect(isRateLimitError(null), isFalse);
      expect(isRateLimitError('checkAvailability failed: not found'), isFalse);
      expect(isRateLimitError('HTTP 404'), isFalse);
      expect(isRateLimitError('downloaded 429 bytes'), isFalse);
    });
  });

  group('rateLimitBackoffDelay', () {
    test('defaults to 30s when no Retry-After is present', () {
      expect(rateLimitBackoffDelay('HTTP 429').inSeconds, 30);
    });

    test('honours a Retry-After value from the message', () {
      expect(rateLimitBackoffDelay('429, retry-after: 12').inSeconds, 12);
      expect(rateLimitBackoffDelay('Retry-After 45 seconds').inSeconds, 45);
    });

    test('clamps to the 5–300s window', () {
      expect(rateLimitBackoffDelay('retry-after: 1').inSeconds, 5);
      expect(rateLimitBackoffDelay('retry-after: 9999').inSeconds, 300);
    });
  });
}
