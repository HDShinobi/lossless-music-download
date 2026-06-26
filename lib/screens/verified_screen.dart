import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../theme/app_tokens.dart';
import '../util/lossless_verdict.dart';
import '../vendor/spotiflac/audio_analysis_widget.dart';

/// Detail screen for a single [LibraryEntry] showing a heuristic lossless
/// badge and the real audio analysis card (decode + FFT spectral cutoff,
/// loudness, dynamic range, and spectrogram), vendored from SpotiFLAC. Once the
/// analysis completes, a conservative real/upscale verdict is derived from the
/// spectral cutoff vs sample rate.
class VerifiedScreen extends ConsumerStatefulWidget {
  const VerifiedScreen({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  ConsumerState<VerifiedScreen> createState() => _VerifiedScreenState();
}

class _VerifiedScreenState extends ConsumerState<VerifiedScreen> {
  AudioAnalysisData? _analysis;

  LibraryEntry get entry => widget.entry;

  /// Strip leading track number ("01 " or "01. ") and file extension.
  String get _displayName {
    final nameWithoutExt = entry.name.contains('.')
        ? entry.name.substring(0, entry.name.lastIndexOf('.'))
        : entry.name;
    return nameWithoutExt.replaceFirst(RegExp(r'^[0-9]+[\s.]\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(entry: entry, displayName: _displayName, tokens: tokens),
          const SizedBox(height: 16),
          _VerifiedBadge(entry: entry, t: t, cs: cs, tokens: tokens),
          if (_analysis != null) ...[
            const SizedBox(height: 12),
            _SpectralVerdict(data: _analysis!, t: t, cs: cs, tokens: tokens),
          ],
          const SizedBox(height: 16),
          // Real spectral analysis (decode → FFT → spectrogram + cutoff).
          AudioAnalysisCard(
            filePath: entry.path,
            onAnalyzed: (data) {
              if (mounted) setState(() => _analysis = data);
            },
          ),
          const SizedBox(height: 16),
          _ServeRow(t: t, cs: cs, tokens: tokens),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spectral verdict (conservative real/upscale heuristic)
// ---------------------------------------------------------------------------

class _SpectralVerdict extends StatelessWidget {
  const _SpectralVerdict({
    required this.data,
    required this.t,
    required this.cs,
    required this.tokens,
  });

  final AudioAnalysisData data;
  final AppLocalizations t;
  final ColorScheme cs;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final verdict = assessLossless(
      codec: data.codec,
      sampleRate: data.sampleRate,
      cutoffHz: data.spectralCutoffHz,
    );

    final (IconData icon, Color color, String label) = switch (verdict) {
      LosslessVerdict.lossless => (
          Icons.verified_rounded,
          cs.primary,
          t.verdictLossless,
        ),
      LosslessVerdict.suspectLossy => (
          Icons.warning_amber_rounded,
          tokens.warn,
          t.verdictSuspect,
        ),
      LosslessVerdict.lossy => (
          Icons.graphic_eq_rounded,
          cs.onSurfaceVariant,
          t.verdictLossy,
        ),
      LosslessVerdict.inconclusive => (
          Icons.help_outline_rounded,
          tokens.muted2,
          t.verdictInconclusive,
        ),
    };

    final cutoff = data.spectralCutoffHz;
    final cutoffText =
        cutoff != null ? '${(cutoff / 1000).toStringAsFixed(1)} kHz' : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                'cutoff $cutoffText',
                style: tokens.mono.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.verdictHeuristicNote,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.entry,
    required this.displayName,
    required this.tokens,
  });

  final LibraryEntry entry;
  final String displayName;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final subtitleParts = <String>[
      if (entry.artistName != null) entry.artistName!,
      if (entry.albumName != null) entry.albumName!,
    ];
    final subtitle = subtitleParts.join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cover placeholder
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: tokens.surface3,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(Icons.music_note, size: 36, color: cs.primary),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Verified Badge
// ---------------------------------------------------------------------------

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({
    required this.entry,
    required this.t,
    required this.cs,
    required this.tokens,
  });

  final LibraryEntry entry;
  final AppLocalizations t;
  final ColorScheme cs;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final isVerified = entry.verified;

    final bgColor = isVerified ? tokens.accentSoft : tokens.surface2;
    final borderColor = isVerified ? tokens.accentLine : cs.outline;
    final iconColor = isVerified ? cs.primary : tokens.muted2;
    final textColor = isVerified ? cs.primary : cs.onSurfaceVariant;
    final badgeIcon = isVerified ? Icons.verified_rounded : Icons.help_outline;
    final badgeLabel = isVerified ? t.verifiedLossless : t.verifiedUnknown;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(badgeIcon, size: 24, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badgeLabel,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isVerified) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.format,
                    style: tokens.mono.copyWith(
                      color: iconColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Serve row
// ---------------------------------------------------------------------------

class _ServeRow extends StatelessWidget {
  const _ServeRow({
    required this.t,
    required this.cs,
    required this.tokens,
  });

  final AppLocalizations t;
  final ColorScheme cs;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/server'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: tokens.surface2,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.cast_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.verifiedServeTitle,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: tokens.muted2),
          ],
        ),
      ),
    );
  }
}
