import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.tabServer)),
      body: Center(child: Text(t.tabServer)),
    );
  }
}
