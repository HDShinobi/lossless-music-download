import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_manager.dart';
import '../providers/library_provider.dart';
import '../theme/app_tokens.dart';
import '../providers/extensions_provider.dart';
import '../util/lossless_verdict.dart';
import '../vendor/spotiflac/audio_analysis_widget.dart';
import '../vendor/spotiflac/replaygain_service.dart';
import '../widgets/convert_sheet.dart';
import '../widgets/edit_metadata_sheet.dart';

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

  // ---- Management actions ----

  Future<void> _edit(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final fields = await showEditMetadataSheet(context, entry);
    if (fields == null || fields.isEmpty) return; // cancelled / nothing changed
    try {
      await ref.read(libraryManagerProvider.notifier).editMetadata(
            entry.path,
            fields,
          );
      messenger.showSnackBar(SnackBar(content: Text(t.editSaved)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.editFailed)));
    }
  }

  Future<void> _reEnrich(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.reEnrichStarted)));
    try {
      await ref.read(libraryManagerProvider.notifier).reEnrich({
        'file_path': entry.path,
        'track_name': entry.title ?? _displayName,
        'artist_name': entry.artistName ?? '',
        'album_name': entry.albumName ?? '',
        'embed_lyrics': true,
        'max_quality': true,
      });
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(t.reEnrichDone)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.reEnrichFailed)));
    }
  }

  Future<void> _replayGain(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.replayGainStarted)));
    final ok = await ReplayGainService.applyToFile(
      entry.path,
      ref.read(backendBridgeProvider),
    );
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? t.replayGainDone : t.replayGainFailed),
    ));
  }

  Future<void> _convert(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showConvertSheet(context);
    if (choice == null) return;
    messenger.showSnackBar(SnackBar(content: Text(t.convertStarted)));
    final newPath = await ref.read(libraryManagerProvider.notifier).convert(
          entry.path,
          choice.format,
          choice.bitrate,
        );
    if (!context.mounted) return;
    if (newPath == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.convertFailed)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(t.convertDone)));
    // The original file was replaced by a new-format file; leave detail view.
    context.pop();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteConfirmTitle),
        content: Text(t.deleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(libraryManagerProvider.notifier).delete(entry.path);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(t.deleteDone)));
    context.pop(); // back to library (which re-scans)
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
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _edit(context);
                case 'reenrich':
                  _reEnrich(context);
                case 'replaygain':
                  _replayGain(context);
                case 'convert':
                  _convert(context);
                case 'delete':
                  _confirmDelete(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(t.manageEdit),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'reenrich',
                child: ListTile(
                  leading: const Icon(Icons.auto_fix_high_outlined),
                  title: Text(t.manageReEnrich),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'replaygain',
                child: ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: Text(t.manageReplayGain),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'convert',
                child: ListTile(
                  leading: const Icon(Icons.transform),
                  title: Text(t.manageConvert),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: Text(t.manageDelete,
                      style: TextStyle(color: cs.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(entry: entry, displayName: _displayName, tokens: tokens),
          const SizedBox(height: 16),
          // One status badge: the format-scan badge until the spectral analysis
          // runs, then the richer spectral verdict replaces it (avoids two
          // near-identical "Lossless" cards).
          if (_analysis == null)
            _VerifiedBadge(entry: entry, t: t, cs: cs, tokens: tokens)
          else
            _SpectralVerdict(data: _analysis!, t: t, cs: cs, tokens: tokens),
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

    final coverPath = entry.coverPath;
    final hasCover = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Album cover (extracted by the library scan), or a placeholder.
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 72,
            height: 72,
            color: tokens.surface3,
            child: hasCover
                ? Image.file(
                    File(coverPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.music_note,
                          size: 36, color: cs.primary),
                    ),
                  )
                : Center(
                    child:
                        Icon(Icons.music_note, size: 36, color: cs.primary),
                  ),
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
