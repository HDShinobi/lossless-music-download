import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_quality.dart';
import 'extensions_provider.dart';

/// Per-path FutureProvider that probes a local audio file via the backend and
/// caches the result for the lifetime of the provider container.
///
/// Returns null when the backend cannot probe the file (missing, unsupported
/// format, or a native bridge error).
final audioQualityProvider = FutureProvider.family<AudioQuality?, String>(
  (ref, path) => ref.read(backendBridgeProvider).getAudioQuality(path),
);
