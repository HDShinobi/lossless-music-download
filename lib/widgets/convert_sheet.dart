import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../vendor/spotiflac/convert_service.dart';

/// User's convert choice.
class ConvertChoice {
  const ConvertChoice(this.format, this.bitrate);
  final String format;
  final String bitrate;
}

/// Shows the convert bottom sheet (format chips + bitrate for lossy targets).
/// Returns the chosen [ConvertChoice], or null if cancelled.
Future<ConvertChoice?> showConvertSheet(BuildContext context) {
  return showModalBottomSheet<ConvertChoice>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _ConvertSheet(),
  );
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet();

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  String _format = 'mp3';
  String _bitrate = convertBitrates.first;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lossy = !isLosslessConvertTarget(_format);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.convertSheetTitle,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final f in convertFormats)
                ChoiceChip(
                  label: Text(f.toUpperCase()),
                  selected: _format == f,
                  onSelected: (_) => setState(() => _format = f),
                ),
            ],
          ),
          if (lossy) ...[
            const SizedBox(height: 16),
            Text(t.convertBitrateLabel,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final b in convertBitrates)
                  ChoiceChip(
                    label: Text(b),
                    selected: _bitrate == b,
                    onSelected: (_) => setState(() => _bitrate = b),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                ConvertChoice(_format, _bitrate),
              ),
              icon: const Icon(Icons.transform),
              label: Text(t.commonConvert),
            ),
          ),
        ],
      ),
    );
  }
}
