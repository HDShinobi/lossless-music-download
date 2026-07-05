import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/extensions_provider.dart';
import '../providers/library_provider.dart';
import '../util/lyrics_parser.dart';

/// Static lyrics viewer for a downloaded track. Fetches LRC via the backend
/// (embedded first, then online) and renders it as a scrollable list. There
/// is no in-app player, so lyrics do not auto-scroll or highlight.
class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key, required this.entry});
  final LibraryEntry entry;

  // Returns (parsed lyrics, isInstrumental). The backend sentinel
  // `[instrumental:true]` is NOT LRC, so the parser must not special-case it —
  // the viewer detects it here and shows a distinct state.
  Future<(ParsedLyrics, bool)> _load(WidgetRef ref) async {
    final bridge = ref.read(backendBridgeProvider);
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.lyricsTitle)),
      body: FutureBuilder<(ParsedLyrics, bool)>(
        future: _load(ref),
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
