import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/preview_player_provider.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/preview_button.dart';

/// Test double: returns a fixed state and records toggle() calls without ever
/// touching the audioplayers platform channel.
class FakePreviewController extends PreviewPlayerController {
  FakePreviewController(this._initial);
  final PreviewPlayerState _initial;
  String? toggledUrl;
  int toggleCount = 0;

  @override
  PreviewPlayerState build() => _initial;

  @override
  Future<void> toggle(String? url) async {
    toggleCount++;
    toggledUrl = url;
  }
}

Future<FakePreviewController> pumpButton(
  WidgetTester tester, {
  required Track track,
  PreviewPlayerState state = const PreviewPlayerState(),
}) async {
  final fake = FakePreviewController(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [previewPlayerProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: PreviewButton(track: track)),
      ),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  const withPreview = Track(
    id: '1',
    name: 'Song',
    artists: 'Artist',
    previewUrl: 'https://cdn/preview.mp3',
  );
  const noPreview = Track(id: '2', name: 'Song', artists: 'Artist');

  group('PreviewButton', () {
    testWidgets('renders nothing when track has no preview', (tester) async {
      await pumpButton(tester, track: noPreview);
      expect(find.byKey(const Key('previewButton')), findsNothing);
    });

    testWidgets('renders the button when a preview is available',
        (tester) async {
      await pumpButton(tester, track: withPreview);
      expect(find.byKey(const Key('previewButton')), findsOneWidget);
    });

    testWidgets('idle shows the outline play icon', (tester) async {
      await pumpButton(tester, track: withPreview);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('playing this url shows the pause icon', (tester) async {
      await pumpButton(
        tester,
        track: withPreview,
        state: const PreviewPlayerState(
          activeUrl: 'https://cdn/preview.mp3',
          status: PreviewStatus.playing,
        ),
      );
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
    });

    testWidgets('paused this url shows the filled play icon', (tester) async {
      await pumpButton(
        tester,
        track: withPreview,
        state: const PreviewPlayerState(
          activeUrl: 'https://cdn/preview.mp3',
          status: PreviewStatus.paused,
        ),
      );
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });

    testWidgets('loading this url shows a spinner', (tester) async {
      await pumpButton(
        tester,
        track: withPreview,
        state: const PreviewPlayerState(
          activeUrl: 'https://cdn/preview.mp3',
          status: PreviewStatus.loading,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('another url playing leaves this button idle', (tester) async {
      await pumpButton(
        tester,
        track: withPreview,
        state: const PreviewPlayerState(
          activeUrl: 'https://cdn/OTHER.mp3',
          status: PreviewStatus.playing,
        ),
      );
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('tap forwards the preview url to toggle', (tester) async {
      final fake = await pumpButton(tester, track: withPreview);
      await tester.tap(find.byKey(const Key('previewButton')));
      await tester.pump();
      expect(fake.toggleCount, 1);
      expect(fake.toggledUrl, 'https://cdn/preview.mp3');
    });
  });
}
