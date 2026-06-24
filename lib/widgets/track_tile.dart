import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/track.dart';
import '../theme/app_tokens.dart';

enum TrackDownloadState { idle, queued, active, done, failed }

/// A branded list-row widget for a single search result track.
///
/// [qualityHint] is optional: `null` renders no badge; non-null renders a pill
/// badge. `'HI-RES'` uses accent colours; any other value uses muted colours.
///
/// Multi-select support:
/// - [selectionMode] when true, shows a checkbox instead of cover art and hides
///   the download button. The whole row tap calls [onSelectToggle].
/// - [selected] the checked state of the checkbox (only used when [selectionMode]).
/// - [onLongPress] called when the user long-presses the tile in normal mode.
/// - [onSelectToggle] called when the user taps the tile in selection mode.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onDownload,
    this.qualityHint,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelectToggle,
    this.downloadState = TrackDownloadState.idle,
  });

  final Track track;
  final VoidCallback onDownload;
  final String? qualityHint;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;
  final TrackDownloadState downloadState;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final tt = Theme.of(context).textTheme;

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Leading: checkbox in selection mode, cover art otherwise
          if (selectionMode)
            Checkbox(
              value: selected,
              onChanged: (_) => onSelectToggle?.call(),
            )
          else
            _CoverArt(track: track),
          const SizedBox(width: 12),
          // Title / artists / badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (qualityHint != null) ...[
                      const SizedBox(width: 6),
                      _QualityBadge(
                        label: qualityHint!,
                        tokens: tokens,
                        cs: cs,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Download button — hidden in selection mode
          if (!selectionMode)
            _DownloadStateIcon(
              downloadState: downloadState,
              onDownload: onDownload,
            ),
        ],
      ),
    );

    return InkWell(
      onTap: selectionMode ? onSelectToggle : null,
      onLongPress: selectionMode ? null : onLongPress,
      child: rowContent,
    );
  }

  String get _subtitle {
    final parts = <String>[track.artists];
    if (track.albumName != null && track.albumName!.isNotEmpty) {
      parts.add(track.albumName!);
    }
    return parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Cover art widget: 48x48 rounded-9 with initial-letter fallback
// ---------------------------------------------------------------------------
class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 48,
        height: 48,
        child: track.coverUrl != null
            ? Image.network(
                track.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, trace) =>
                    _InitialFallback(name: track.name, tokens: tokens, cs: cs),
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: tokens.surface2,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
              )
            : _InitialFallback(name: track.name, tokens: tokens, cs: cs),
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({
    required this.name,
    required this.tokens,
    required this.cs,
  });

  final String name;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: tokens.surface3,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download state icon
// ---------------------------------------------------------------------------
class _DownloadStateIcon extends StatelessWidget {
  const _DownloadStateIcon({required this.downloadState, required this.onDownload});

  final TrackDownloadState downloadState;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (downloadState) {
      TrackDownloadState.idle => IconButton(
          icon: const Icon(Icons.download_outlined),
          onPressed: onDownload,
          tooltip: Localizations.of<AppLocalizations>(context, AppLocalizations)?.download,
        ),
      TrackDownloadState.queued => Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.schedule, size: 20, color: cs.onSurfaceVariant),
        ),
      TrackDownloadState.active => const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      TrackDownloadState.done => Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.check_circle_outline, size: 20, color: cs.primary),
        ),
      TrackDownloadState.failed => Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.error_outline, size: 20, color: cs.error),
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Quality badge pill
// ---------------------------------------------------------------------------
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.label,
    required this.tokens,
    required this.cs,
  });

  final String label;
  final AppTokens tokens;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isHiRes = label == 'HI-RES';
    final bg = isHiRes ? tokens.accentSoft : tokens.surface2;
    final textColor = isHiRes ? cs.primary : cs.onSurfaceVariant;
    final borderColor = isHiRes ? tokens.accentLine : cs.outline;

    return Container(
      key: const Key('qualityBadge'),
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
