import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/main.dart';

void main() {
  testWidgets('tapping Library tab shows Library screen', (t) async {
    await t.pumpWidget(const ProviderScope(child: MyApp()));
    await t.pumpAndSettle();
    expect(find.text('Tìm'), findsWidgets); // default vi, Search tab
    await t.tap(find.text('Thư viện'));
    await t.pumpAndSettle();
    expect(find.text('Thư viện'), findsWidgets);
  });
}
