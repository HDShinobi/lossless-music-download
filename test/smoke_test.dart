import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/main.dart';

void main() {
  testWidgets('app boots inside ProviderScope', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Tìm'), findsWidgets); // default vi Search tab
  });
}
