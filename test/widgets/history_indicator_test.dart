import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/track_tile.dart';

void main() {
  testWidgets(
    'history badge is localized and leaves download action available',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: Scaffold(
            body: TrackTile(
              track: const Track(id: 'song', name: 'Song', artists: 'Artist'),
              downloaded: true,
              onDownload: () => taps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyDownloaded')), findsOneWidget);
      expect(find.byTooltip('Đã tải'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.download_outlined));
      expect(taps, 1);
    },
  );
}
