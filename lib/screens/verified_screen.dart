import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/spectrogram_placeholder.dart';

/// Detail screen for a single [LibraryEntry] showing a heuristic lossless
/// badge, an illustrative spectrogram placeholder, and a stats grid.
///
/// All audio metrics (bit depth, sample rate) are shown as '—' because a
/// real backend audio-probe does not exist yet.
class VerifiedScreen extends StatelessWidget {
  const VerifiedScreen({super.key, required this.entry});

  final LibraryEntry entry;

  /// Strip leading track number ("01 " or "01. ") and file extension.
  String get _displayName {
    final nameWithoutExt = entry.name.contains('.')
        ? entry.name.substring(0, entry.name.lastIndexOf('.'))
        : entry.name;
    return nameWithoutExt.replaceFirst(RegExp(r'^[0-9]+[\s.]\s*'), '');
  }

  String get _sizeLabel {
    final mb = entry.sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
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
          const SizedBox(height: 16),
          const SpectrogramPlaceholder(),
          const SizedBox(height: 6),
          Text(
            t.verifiedSpectrumNote,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.muted2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _StatsGrid(entry: entry, sizeLabel: _sizeLabel, t: t, tokens: tokens, cs: cs),
          const SizedBox(height: 16),
          _ServeRow(t: t, cs: cs, tokens: tokens),
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
// Stats Grid
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.entry,
    required this.sizeLabel,
    required this.t,
    required this.tokens,
    required this.cs,
  });

  final LibraryEntry entry;
  final String sizeLabel;
  final AppLocalizations t;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (t.statFormat, entry.format),
      (t.statSize, sizeLabel),
      (t.statBitDepth, '—'),
      (t.statSampleRate, '—'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.8,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: stats
          .map((s) => _StatCell(label: s.$1, value: s.$2, tokens: tokens, cs: cs))
          .toList(),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.tokens,
    required this.cs,
  });

  final String label;
  final String value;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: tokens.muted2,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.mono.copyWith(
              fontSize: 13,
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
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
