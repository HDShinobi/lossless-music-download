import 'package:flutter/material.dart';
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
    this.onRowTap,
    this.qualityHint,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelectToggle,
    this.onArtistTap,
    this.onAlbumTap,
    this.downloadState = TrackDownloadState.idle,
  });

  final Track track;
  /// Called by the download icon button — quick download without picker.
  final VoidCallback onDownload;
  /// Called when the row itself is tapped in normal mode.
  /// If null, falls back to [onDownload] (original behavior).
  final VoidCallback? onRowTap;
  final String? qualityHint;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;
  /// Called when the artist name is tapped (only when artistId is available).
  final VoidCallback? onArtistTap;
  /// Called when the album name is tapped (only when albumId is available).
  final VoidCallback? onAlbumTap;
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
                      child: _SubtitleRow(
                        track: track,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        linkColor: cs.primary,
                        onArtistTap: onArtistTap,
                        onAlbumTap: onAlbumTap,
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
                    if (track.isAtmos) ...[
                      const SizedBox(width: 4),
                      _QualityBadge(
                        label: 'ATMOS',
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
            Material(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onDownload,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _DownloadStateIcon(state: downloadState, cs: cs),
                ),
              ),
            ),
        ],
      ),
    );

    return InkWell(
      onTap: selectionMode ? onSelectToggle : (onRowTap ?? onDownload),
      onLongPress: selectionMode ? null : onLongPress,
      child: rowContent,
    );
  }

}

// ---------------------------------------------------------------------------
// Subtitle row: clickable artist and album names
// ---------------------------------------------------------------------------
class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({
    required this.track,
    required this.style,
    required this.linkColor,
    this.onArtistTap,
    this.onAlbumTap,
  });

  final Track track;
  final TextStyle? style;
  final Color linkColor;
  final VoidCallback? onArtistTap;
  final VoidCallback? onAlbumTap;

  @override
  Widget build(BuildContext context) {
    final canTapArtist = onArtistTap != null && track.artistId != null;
    final canTapAlbum = onAlbumTap != null &&
        track.albumId != null &&
        track.albumName != null &&
        track.albumName!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: canTapArtist ? onArtistTap : null,
            child: Text(
              track.artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: canTapArtist
                  ? style?.copyWith(
                      color: linkColor,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor.withValues(alpha: 0.5),
                    )
                  : style,
            ),
          ),
        ),
        if (track.albumName != null && track.albumName!.isNotEmpty) ...[
          Text(' · ', style: style),
          Flexible(
            child: GestureDetector(
              onTap: canTapAlbum ? onAlbumTap : null,
              child: Text(
                track.albumName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: canTapAlbum
                    ? style?.copyWith(
                        color: linkColor,
                        decoration: TextDecoration.underline,
                        decorationColor: linkColor.withValues(alpha: 0.5),
                      )
                    : style,
              ),
            ),
          ),
        ],
      ],
    );
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
  const _DownloadStateIcon({required this.state, required this.cs});

  final TrackDownloadState state;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      TrackDownloadState.idle => Icon(
          Icons.download_outlined,
          size: 20,
          color: cs.onPrimaryContainer,
        ),
      TrackDownloadState.queued => Icon(
          Icons.schedule,
          size: 20,
          color: cs.onPrimaryContainer.withValues(alpha: 0.6),
        ),
      TrackDownloadState.active => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.onPrimaryContainer,
          ),
        ),
      TrackDownloadState.done => Icon(
          Icons.check_circle_outline,
          size: 20,
          color: cs.primary,
        ),
      TrackDownloadState.failed => Icon(
          Icons.error_outline,
          size: 20,
          color: cs.error,
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
    final isAtmos = label == 'ATMOS';
    final bg = isHiRes
        ? tokens.accentSoft
        : isAtmos
            ? const Color(0xFF1A1040)
            : tokens.surface2;
    final textColor = isHiRes
        ? cs.primary
        : isAtmos
            ? const Color(0xFFB09FE8)
            : cs.onSurfaceVariant;
    final borderColor = isHiRes
        ? tokens.accentLine
        : isAtmos
            ? const Color(0xFF6B4EBF)
            : cs.outline;

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
