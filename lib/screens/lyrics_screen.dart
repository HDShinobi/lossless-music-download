import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/extensions_provider.dart';
import '../providers/library_provider.dart';
import '../util/lyrics_parser.dart';

/// Static lyrics viewer for a downloaded track. Fetches LRC via the backend
/// (embedded first, then online) and renders it as a scrollable list. There
/// is no in-app player, so lyrics do not auto-scroll or highlight.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  late final Future<(ParsedLyrics, bool)> _future;

  @override
  void initState() {
    super.initState();
    // Created once here (not in build()) so framework-driven rebuilds — e.g.
    // system theme/locale changes — don't reset the screen to a spinner and
    // re-issue the backend fetch(es).
    _future = _load();
  }

  // Returns (parsed lyrics, isInstrumental). The backend sentinel
  // `[instrumental:true]` is NOT LRC, so the parser must not special-case it —
  // the viewer detects it here and shows a distinct state.
  Future<(ParsedLyrics, bool)> _load() async {
    final bridge = ref.read(backendBridgeProvider);
    final entry = widget.entry;
    final name = entry.title ?? entry.name;
    final artist = entry.artistName ?? '';
    // Embedded first (works offline for downloaded files); fall back to online.
    var lrc = await bridge.getLyricsLRC(
        trackName: name, artistName: artist, filePath: entry.path);
    if (lrc.trim().isEmpty || lrc.trim() == '[instrumental:true]') {
      lrc = await bridge.getLyricsLRC(trackName: name, artistName: artist);
    }
    final instrumental = lrc.trim() == '[instrumental:true]';
    return (
      instrumental ? ParsedLyrics.empty : LyricsParser.parse(lrc),
      instrumental
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.lyricsTitle)),
      body: FutureBuilder<(ParsedLyrics, bool)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final (parsed, instrumental) = snap.data ?? (ParsedLyrics.empty, false);
          if (instrumental) {
            return Center(child: Text(t.lyricsInstrumental));
          }
          if (parsed.isEmpty) {
            return Center(child: Text(t.lyricsNotFound));
          }
          final lines = parsed.synced
              ? parsed.lines.map((l) => l.text).toList()
              : parsed.plainText.split('\n');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lines.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(lines[i], style: Theme.of(context).textTheme.titleMedium),
            ),
          );
        },
      ),
    );
  }
}
