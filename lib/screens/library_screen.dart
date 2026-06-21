import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.tabLibrary)),
      body: Center(child: Text(t.tabLibrary)),
    );
  }
}
