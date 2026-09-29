import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/server_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

class _Bridge extends BackendBridge {
  ServerStatus status = const ServerStatus(
    running: true,
    url: 'http://10.0.0.2:8200',
  );
  int reads = 0;

  @override
  Future<ServerStatus> getMediaServerStatus() async {
    reads++;
    return status;
  }
}

void main() {
  testWidgets(
    'screen refreshes spontaneous server stop without loading spinner',
    (tester) async {
      final bridge = _Bridge();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendBridgeProvider.overrideWithValue(bridge),
            downloadDirProvider.overrideWith((_) async => '/music'),
          ],
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ServerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stop server'), findsOneWidget);
      bridge.status = ServerStatus.stopped;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(bridge.reads, greaterThanOrEqualTo(2));
      expect(find.text('Start server'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final readsAfterUnmount = bridge.reads;
      await tester.pump(const Duration(seconds: 5));
      expect(bridge.reads, readsAfterUnmount);
    },
  );
}
