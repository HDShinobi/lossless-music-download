import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/utils/extension_auth_launcher.dart';

void main() {
  group('isExtensionVerificationRequired', () {
    test('matches the textual VERIFY_REQUIRED family', () {
      expect(isExtensionVerificationRequired('VERIFY_REQUIRED'), isTrue);
      expect(isExtensionVerificationRequired('needs verification'), isTrue);
      expect(
        isExtensionVerificationRequired('signed session is not authenticated'),
        isTrue,
      );
      expect(isExtensionVerificationRequired('Unauthorized'), isTrue);
      expect(isExtensionVerificationRequired('precondition required'), isTrue);
    });

    test('matches numeric HTTP 401 / 428 statuses in various shapes', () {
      expect(isExtensionVerificationRequired('download failed: HTTP 401'),
          isTrue);
      expect(isExtensionVerificationRequired('session exchange failed: HTTP 428'),
          isTrue);
      expect(isExtensionVerificationRequired('status 401'), isTrue);
      expect(isExtensionVerificationRequired('428: precondition'), isTrue);
      expect(isExtensionVerificationRequired('got 401 for /session'), isTrue);
    });

    test('does not match unrelated errors or unrelated numbers', () {
      expect(isExtensionVerificationRequired('network error'), isFalse);
      expect(isExtensionVerificationRequired('HTTP 404 not found'), isFalse);
      expect(isExtensionVerificationRequired('downloaded 401 bytes'), isFalse);
      expect(isExtensionVerificationRequired('HTTP 500'), isFalse);
    });
  });

  group('showExtensionVerificationHelpDialog', () {
    final authUri =
        Uri.parse('https://api.zarz.moe/v2/challenge?id=abc123&cb=spotiflac');

    testWidgets('shows the verification URL and copy/open actions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showExtensionVerificationHelpDialog(
                    context,
                    authUri,
                    immediateFailure: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(authUri.toString()), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser), findsOneWidget);
    });
  });
}
