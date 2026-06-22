import 'package:flutter/material.dart';
import '../models/installed_extension.dart';
import '../models/track.dart';
import '../theme/app_tokens.dart';
import '../l10n/app_localizations.dart';

/// The result of a user's selection in the download sheet.
class DownloadChoice {
  const DownloadChoice({this.sourceId, this.quality});

  final String? sourceId;
  final String? quality;
}

// ---------------------------------------------------------------------------
// Quality options (label, tech description, short key)
// ---------------------------------------------------------------------------
const _kQualityOptions = [
  _QualityOption(label: 'FLAC · Hi-Res', desc: 'FLAC 24-bit / 96.0 kHz', value: 'hires'),
  _QualityOption(label: 'FLAC · CD', desc: 'FLAC 16-bit / 44.1 kHz', value: 'cd'),
  _QualityOption(label: 'MP3', desc: '320 kbps', value: 'mp3'),
];

class _QualityOption {
  const _QualityOption({
    required this.label,
    required this.desc,
    required this.value,
  });

  final String label;
  final String desc;
  final String value;
}

/// Shows the bottom-sheet and returns a [DownloadChoice] or null (cancelled).
Future<DownloadChoice?> showDownloadSheet(
  BuildContext context, {
  required Track track,
  required List<InstalledExtension> sources,
}) {
  return showModalBottomSheet<DownloadChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DownloadSheet(track: track, sources: sources),
  );
}

// ---------------------------------------------------------------------------
// Sheet widget — StatefulWidget for local selection state
// ---------------------------------------------------------------------------
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.track, required this.sources});

  final Track track;
  final List<InstalledExtension> sources;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  late String? _selectedSourceId;
  late String _selectedQuality;

  @override
  void initState() {
    super.initState();
    _selectedSourceId =
        widget.sources.isNotEmpty ? widget.sources.first.id : null;
    _selectedQuality = _kQualityOptions.first.value;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tokens = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Track header
            Row(
              children: [
                // Small cover / initial-letter fallback (42px)
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: widget.track.coverUrl != null
                        ? Image.network(
                            widget.track.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _coverFallback(widget.track.name, tokens, cs),
                          )
                        : _coverFallback(widget.track.name, tokens, cs),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            tt.bodyMedium?.copyWith(color: cs.onSurface),
                      ),
                      Text(
                        widget.track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // "Nguon" section
            Text(
              t.downloadSheetSource,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (widget.sources.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.warnSoft,
                  border: Border.all(color: tokens.warnLine),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.downloadSheetNoSources,
                  style: tt.bodySmall?.copyWith(color: tokens.warn),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.sources.map((src) {
                  final isSelected = _selectedSourceId == src.id;
                  return _SourceChip(
                    source: src,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedSourceId = src.id),
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),

            // "Chat luong" section
            Text(
              t.downloadSheetQuality,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: _selectedQuality,
              onChanged: (v) {
                if (v != null) setState(() => _selectedQuality = v);
              },
              child: Column(
                children: _kQualityOptions.map((opt) {
                  return RadioListTile<String>(
                    value: opt.value,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      opt.label,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                    ),
                    subtitle: Text(
                      opt.desc,
                      style: tokens.mono.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // CTA
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // No download source -> nothing to download from; disable.
                onPressed: widget.sources.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                          DownloadChoice(
                            sourceId: _selectedSourceId,
                            quality: _selectedQuality,
                          ),
                        ),
                child: Text(t.downloadCta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _coverFallback(String name, AppTokens tokens, ColorScheme cs) {
  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
  return Container(
    color: tokens.surface3,
    child: Center(
      child: Text(
        initial,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Source chip
// ---------------------------------------------------------------------------
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.source,
    required this.isSelected,
    required this.onTap,
  });

  final InstalledExtension source;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accentSoft : tokens.surface2,
          border: Border.all(
            color: isSelected ? tokens.accentLine : cs.outline,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Health dot
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              source.displayName,
              style: TextStyle(
                color: isSelected ? cs.primary : cs.onSurface,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
