import 'dart:io';

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

  String get _displayName {
    if (entry.title != null && entry.title!.isNotEmpty) return entry.title!;
    final nameWithoutExt = entry.name.contains('.')
        ? entry.name.substring(0, entry.name.lastIndexOf('.'))
        : entry.name;
    return nameWithoutExt.replaceFirst(RegExp(r'^[0-9]+[\s.]\s*'), '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final tt = Theme.of(context).textTheme;

    final qualityAsync = ref.watch(audioQualityProvider(entry.path));
    final quality = qualityAsync.value;

    final subtitle = [
      if (entry.artistName != null) entry.artistName!,
      if (entry.albumName != null) entry.albumName!,
    ].join(' · ');
    final subtitleIsInferred = entry.tagsFromFallback && subtitle.isNotEmpty;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _CoverArt(entry: entry, tokens: tokens, cs: cs),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: subtitleIsInferred
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    _FormatBadge(
                        label: entry.format, tokens: tokens, cs: cs),
                    if (quality != null && quality.hasData) ...[
                      const SizedBox(width: 4),
                      _QualityBadge(
                          quality: quality, tokens: tokens, cs: cs),
                    ],
                    if (entry.tagsFromFallback) ...[
                      const SizedBox(width: 4),
                      _TagsMissingBadge(tokens: tokens, cs: cs),
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
// Cover art — local file extracted by Go scanner, fallback to placeholder
// ---------------------------------------------------------------------------
class _CoverArt extends StatelessWidget {
  const _CoverArt(
      {required this.entry, required this.tokens, required this.cs});

  final LibraryEntry entry;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final coverPath = entry.coverPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: coverPath != null
            ? Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: tokens.surface3,
        child: Center(
          child: Icon(Icons.music_note, size: 22, color: cs.onSurfaceVariant),
        ),
      );
}

// ---------------------------------------------------------------------------
// Format badge pill
// ---------------------------------------------------------------------------
class _FormatBadge extends StatelessWidget {
  const _FormatBadge(
      {required this.label, required this.tokens, required this.cs});

  final String label;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isFlac = label == 'FLAC';
    return Container(
      key: const Key('formatBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isFlac ? tokens.accentSoft : tokens.surface2,
        border: Border.all(
            color: isFlac ? tokens.accentLine : cs.outline, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isFlac ? cs.primary : cs.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tags-missing badge — shown when metadata was inferred from folder path
// ---------------------------------------------------------------------------
class _TagsMissingBadge extends StatelessWidget {
  const _TagsMissingBadge({required this.tokens, required this.cs});

  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tagsMissingBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.downSoft,
        border: Border.all(color: tokens.down.withValues(alpha: 0.3), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'tags missing',
        style: TextStyle(
          color: tokens.down,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quality badge pill — "24/96" for lossless, "44.1k" for lossy
// ---------------------------------------------------------------------------
class _QualityBadge extends StatelessWidget {
  const _QualityBadge(
      {required this.quality, required this.tokens, required this.cs});

  final AudioQuality quality;
  final AppTokens tokens;
  final ColorScheme cs;

  String get _label {
    final khz = quality.sampleRate / 1000;
    final kStr = khz == khz.truncateToDouble()
        ? khz.toInt().toString()
        : khz.toStringAsFixed(1);
    if (quality.bitDepth > 0) return '${quality.bitDepth}/$kStr';
    return '${kStr}k';
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
