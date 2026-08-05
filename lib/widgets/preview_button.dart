import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/preview_player_provider.dart';

/// A per-row play/pause button that streams a track's 30s preview snippet.
///
/// Renders nothing when the track has no `preview_url`, so it can be dropped
/// into any list row unconditionally. Only one preview plays at a time
/// (enforced by [previewPlayerProvider]).
class PreviewButton extends ConsumerWidget {
  const PreviewButton({super.key, required this.track, this.size = 24});

  final Track track;
  final double size;

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(previewPlayerProvider.notifier).toggle(track.previewUrl);
    } catch (_) {
      if (!context.mounted) return;
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.previewUnavailable)),
      );
    }
  }

  /// Wraps the play/pause glyph in a determinate ring showing how far into the
  /// 30s snippet playback is (0..1 from [PreviewPlayerState.progress]).
  Widget _withProgressRing(Widget glyph, double progress, ColorScheme cs) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            key: const Key('previewProgress'),
            value: progress,
            strokeWidth: 2,
            color: cs.primary,
            backgroundColor: cs.primary.withValues(alpha: 0.2),
          ),
          glyph,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!track.hasPreview) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);

    final previewState = ref.watch(previewPlayerProvider);
    final isActive = previewState.isActiveUrl(track.previewUrl);
    final status = isActive ? previewState.status : PreviewStatus.idle;

    final Widget icon;
    final String tooltip;
    switch (status) {
      case PreviewStatus.loading:
        icon = SizedBox(
          width: size * 0.7,
          height: size * 0.7,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        );
        tooltip = t.previewStop;
        break;
      case PreviewStatus.playing:
        icon = _withProgressRing(
          Icon(Icons.pause_circle_filled_rounded,
              size: size * 0.72, color: cs.primary),
          previewState.progress,
          cs,
        );
        tooltip = t.previewStop;
        break;
      case PreviewStatus.paused:
        icon = _withProgressRing(
          Icon(Icons.play_circle_fill_rounded,
              size: size * 0.72, color: cs.primary),
          previewState.progress,
          cs,
        );
        tooltip = t.previewPlay;
        break;
      case PreviewStatus.idle:
        icon = Icon(
          Icons.play_circle_outline_rounded,
          color: cs.onSurfaceVariant,
        );
        tooltip = t.previewPlay;
        break;
    }

    return IconButton(
      key: const Key('previewButton'),
      iconSize: size,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: icon,
      tooltip: tooltip,
      onPressed: () => _onPressed(context, ref),
    );
  }
}
