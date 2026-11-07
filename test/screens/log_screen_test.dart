import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/engine_version.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/screens/log_screen.dart';
import 'package:lossless_music_download/services/app_log.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    AppLog.instance.clear();
    PackageInfo.setMockInitialValues(
      appName: 'Lossless Music',
      packageName: 'test',
      version: '0.11.0',
      buildNumber: '23',
      buildSignature: '',
    );
  });

  tearDown(() => AppLog.instance.clear());

  Future<void> open(WidgetTester tester, [String locale = 'en']) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LogScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders live entries in chronological order and versions', (
    tester,
  ) async {
    AppLog.instance.add(LogLevel.info, 'Test', 'first entry');
    AppLog.instance.add(LogLevel.error, 'Test', 'second entry');
    await open(tester);
    expect(find.textContaining('0.11.0'), findsOneWidget);
    expect(find.textContaining(kEngineVersion), findsOneWidget);
    final first = find.textContaining('first entry');
    final second = find.textContaining('second entry');
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.widget<Text>(first).style?.fontFamily, 'monospace');
    AppLog.instance.add(LogLevel.warning, 'Test', 'live entry');
    await tester.pumpAndSettle();
    expect(find.textContaining('live entry'), findsOneWidget);
  });

  testWidgets('filters All, Warn+, Error and clears the entire buffer', (
    tester,
  ) async {
    AppLog.instance.add(LogLevel.info, 'Test', 'info entry');
    AppLog.instance.add(LogLevel.warning, 'Test', 'warn entry');
    AppLog.instance.add(LogLevel.error, 'Test', 'error entry');
    await open(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Warn+'));
    await tester.pumpAndSettle();
    expect(find.textContaining('info entry'), findsNothing);
    expect(find.textContaining('warn entry'), findsOneWidget);
    expect(find.textContaining('error entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('warn entry'), findsNothing);
    expect(find.textContaining('error entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('info entry'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(AppLog.instance.entries, isEmpty);
    expect(find.text('No logs yet'), findsOneWidget);
  });

  testWidgets('Copy all includes redacted hidden entries and version header', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    AppLog.instance.add(LogLevel.info, 'Test', 'token=private');
    AppLog.instance.add(LogLevel.error, 'Test', 'error entry');
    await open(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Error'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy all'));
    await tester.pumpAndSettle();
    final text =
        (calls.singleWhere((c) => c.method == 'Clipboard.setData').arguments
                as Map)['text']
            as String;
    expect(text, contains('0.11.0'));
    expect(text, contains(kEngineVersion));
    expect(text, contains('token=[REDACTED]'));
    expect(text, isNot(contains('private')));
    expect(text, contains('error entry'));
    expect(find.text('Logs copied'), findsOneWidget);
  });

  testWidgets('shows Vietnamese labels', (tester) async {
    await open(tester, 'vi');
    expect(find.text('Nhật ký'), findsOneWidget);
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Cảnh báo trở lên'), findsOneWidget);
    expect(find.text('Lỗi'), findsOneWidget);
    expect(find.byTooltip('Sao chép tất cả'), findsOneWidget);
    expect(find.byTooltip('Xóa nhật ký'), findsOneWidget);
  });
}
