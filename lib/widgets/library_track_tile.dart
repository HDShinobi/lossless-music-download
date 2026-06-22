import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_quality.dart';
import '../providers/audio_quality_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_tokens.dart';

/// A branded list-row widget for a single library track entry.
class LibraryTrackTile extends ConsumerWidget {
  const LibraryTrackTile({
    super.key,
    required this.entry,
    this.onTap,
  });

  final LibraryEntry entry;
  final VoidCallback? onTap;

  /// Strip leading track number like "01 " or "01. " from the display name.
  String get _displayName {
    final nameWithoutExt = entry.name.contains('.')
        ? entry.name.substring(0, entry.name.lastIndexOf('.'))
        : entry.name;
    return nameWithoutExt.replaceFirst(RegExp(r'^[0-9]+[\s.]\s*'), '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    // Watch the audio quality probe — non-blocking; tile renders immediately
    // with the format badge and fills in the quality badge when resolved.
    final qualityAsync = ref.watch(audioQualityProvider(entry.path));
    final quality = qualityAsync.value;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Cover placeholder
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.surface3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(Icons.music_note, size: 20, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          // Title + badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _FormatBadge(label: entry.format, tokens: tokens, cs: cs),
                    if (quality != null && quality.hasData) ...[
                      const SizedBox(width: 4),
                      _QualityBadge(
                        quality: quality,
                        tokens: tokens,
                        cs: cs,
                      ),
                    ],
                    if (entry.verified) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified,
                        key: const Key('verifiedCheck'),
                        size: 14,
                        color: cs.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, child: row);
    }
    return row;
  }
}

// ---------------------------------------------------------------------------
// Format badge pill — matches _QualityBadge visual from track_tile.dart
// ---------------------------------------------------------------------------
class _FormatBadge extends StatelessWidget {
  const _FormatBadge({
    required this.label,
    required this.tokens,
    required this.cs,
  });

  final String label;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isFlac = label == 'FLAC';
    final bg = isFlac ? tokens.accentSoft : tokens.surface2;
    final textColor = isFlac ? cs.primary : cs.onSurfaceVariant;
    final borderColor = isFlac ? tokens.accentLine : cs.outline;

    return Container(
      key: const Key('formatBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quality badge pill — shows bit-depth/sample-rate (e.g. "24/96" or "44.1k")
// ---------------------------------------------------------------------------
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.quality,
    required this.tokens,
    required this.cs,
  });

  final AudioQuality quality;
  final AppTokens tokens;
  final ColorScheme cs;

  /// Format: "24/96" when bit depth is known, "44.1k" for lossy (bitDepth==0).
  String get _label {
    final khz = quality.sampleRate / 1000;
    if (quality.bitDepth > 0) {
      final kStr = khz == khz.truncateToDouble()
          ? khz.toInt().toString()
          : khz.toStringAsFixed(1);
      return '${quality.bitDepth}/$kStr';
    }
    // Lossy — show only kHz with 'k' suffix, trimming trailing zeros.
    final kStr = khz == khz.truncateToDouble()
        ? '${khz.toInt()}k'
        : '${khz.toStringAsFixed(1)}k';
    return kStr;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('qualityBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.surface2,
        border: Border.all(color: cs.outline, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: tokens.mono.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
