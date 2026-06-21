import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.tabQueue)),
      body: Center(child: Text(t.tabQueue)),
    );
  }
}
