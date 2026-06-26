import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/apk_downloader.dart';
import '../services/update_checker.dart';

/// Shows the "update available" dialog for [info]. Downloads the APK with a
/// progress bar and launches the installer. Returns when dismissed.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress; // null = indeterminate
  String? _error;

  Future<void> _downloadAndInstall() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      final path = await ApkDownloader.download(
        widget.info.apkUrl,
        widget.info.version,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      await ApkDownloader.install(path);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = t.updateFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final changelog = widget.info.changelog.trim();

    return AlertDialog(
      title: Text(t.updateAvailableTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.updateNewVersionLabel(widget.info.version),
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
            ),
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                changelog,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                _progress == null
                    ? t.updateDownloading
                    : '${(_progress! * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.updateLater),
          ),
        FilledButton(
          onPressed: _downloading ? null : _downloadAndInstall,
          child: Text(t.updateDownloadInstall),
        ),
      ],
    );
  }
}
