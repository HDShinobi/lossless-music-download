import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../engine_version.dart';
import '../services/app_log.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  LogLevel? _minimumLevel;
  String? _appVersion;
  int? _updateFrame;

  @override
  void initState() {
    super.initState();
    AppLog.instance.addListener(_onLogUpdate);
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // The log viewer remains usable if package metadata is unavailable.
    }
  }

  void _onLogUpdate() {
    // Logs can arrive during a build or in bursts. Rebuild once next frame.
    _updateFrame ??= WidgetsBinding.instance.scheduleFrameCallback((_) {
      _updateFrame = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    AppLog.instance.removeListener(_onLogUpdate);
    if (_updateFrame != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(_updateFrame!);
    }
    super.dispose();
  }

  String _versionHeader(AppLocalizations t) =>
      '${_appVersion == null ? t.logsVersionUnavailable : t.logsAppVersion(_appVersion!)}'
      ' · ${t.logsEngineVersion(kEngineVersion)}';

  Future<void> _copyAll() async {
    final t = AppLocalizations.of(context);
    final text = [
      _versionHeader(t),
      ...AppLog.instance.entries.map((entry) => entry.toString()),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.logsCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final entries = AppLog.instance.entries
        .where(
          (entry) =>
              _minimumLevel == null ||
              entry.level.index >= _minimumLevel!.index,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(t.logsTitle),
        actions: [
          IconButton(
            tooltip: t.logsCopyAll,
            icon: const Icon(Icons.copy_outlined),
            onPressed: _copyAll,
          ),
          IconButton(
            tooltip: t.logsClear,
            icon: const Icon(Icons.delete_outline),
            onPressed: AppLog.instance.clear,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _versionHeader(t),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (level, label) in [
                  (null, t.logsAll),
                  (LogLevel.warning, t.logsWarnPlus),
                  (LogLevel.error, t.logsError),
                ])
                  FilterChip(
                    label: Text(label),
                    selected: _minimumLevel == level,
                    onSelected: (_) => setState(() => _minimumLevel = level),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(t.logsEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    reverse: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[entries.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          entry.toString(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: entry.level == LogLevel.error
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
