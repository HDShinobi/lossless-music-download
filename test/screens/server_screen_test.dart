import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/server_provider.dart';
import 'package:lossless_music_download/screens/server_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fake ServerController — overrides build() to return a fixed status.
// ---------------------------------------------------------------------------
class _FakeServerController extends ServerController {
  final ServerStatus _fixed;
  _FakeServerController(this._fixed);

  @override
  Future<ServerStatus> build() async => _fixed;
}

Widget buildServerScreen(List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const ServerScreen(),
    ),
  );
}

void main() {
  group('ServerScreen widget tests', () {
    testWidgets('stopped state shows "Start server" button', (tester) async {
      await tester.pumpWidget(
        buildServerScreen([
          serverProvider
              .overrideWith(() => _FakeServerController(ServerStatus.stopped)),
          downloadDirProvider.overrideWith((_) async => '/test/downloads'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start server'), findsOneWidget);
      expect(find.text('Stop server'), findsNothing);
    });

    testWidgets('running state shows URL and "Stop server" button',
        (tester) async {
      const running = ServerStatus(
        running: true,
        url: 'http://10.0.0.5:8200/',
        name: 'Lossless Music',
      );

      await tester.pumpWidget(
        buildServerScreen([
          serverProvider
              .overrideWith(() => _FakeServerController(running)),
          downloadDirProvider.overrideWith((_) async => '/test/downloads'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stop server'), findsOneWidget);
      expect(find.text('Start server'), findsNothing);
      expect(find.textContaining('10.0.0.5:8200'), findsOneWidget);
    });
  });
}
