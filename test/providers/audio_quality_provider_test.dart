import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/audio_quality.dart';
import 'package:lossless_music_download/providers/audio_quality_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — overrides only getAudioQuality; no real MethodChannel calls.
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  final AudioQuality? _fixed;

  _FakeBridge(this._fixed);

  @override
  Future<AudioQuality?> getAudioQuality(String path) async => _fixed;
}

void main() {
  group('audioQualityProvider', () {
    test('resolves to the value returned by the bridge', () async {
      const expected = AudioQuality(
        bitDepth: 24,
        sampleRate: 96000,
        bitrate: 2304,
        durationSec: 245,
        codec: 'flac',
      );

      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(_FakeBridge(expected)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(audioQualityProvider('/x.flac').future);

      expect(result, isNotNull);
      expect(result!.bitDepth, 24);
      expect(result.sampleRate, 96000);
      expect(result.bitrate, 2304);
      expect(result.hasData, isTrue);
      expect(result.bitDepthLabel, '24-bit');
      expect(result.sampleRateLabel, '96.0 kHz');
    });

    test('resolves to null when bridge returns null', () async {
      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(_FakeBridge(null)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(audioQualityProvider('/bad.mp3').future);

      expect(result, isNull);
    });

    test('different paths are cached independently (family)', () async {
      const q24 = AudioQuality(bitDepth: 24, sampleRate: 96000);
      // The fake always returns the same value; we test that two paths
      // each produce their own provider slot (no cross-contamination).
      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(_FakeBridge(q24)),
        ],
      );
      addTearDown(container.dispose);

      final a = await container.read(audioQualityProvider('/a.flac').future);
      final b = await container.read(audioQualityProvider('/b.flac').future);

      expect(a?.sampleRate, 96000);
      expect(b?.sampleRate, 96000);
      // Providers are distinct objects (different family args).
      expect(
        audioQualityProvider('/a.flac') == audioQualityProvider('/b.flac'),
        isFalse,
      );
    });
  });
}
