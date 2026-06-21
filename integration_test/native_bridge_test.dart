import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.losslessmusic/native');

  testWidgets('native ping returns pong', (tester) async {
    final res = await channel.invokeMethod<String>('ping');
    expect(res, 'pong');
  });

  testWidgets('backend getDownloadProgress returns JSON', (tester) async {
    final res = await channel.invokeMethod<String>('getDownloadProgress');
    expect(res, isNotNull);
    expect(() => jsonDecode(res!), returnsNormally); // valid JSON
  });

  testWidgets('getAllProgress returns JSON', (tester) async {
    final res = await channel.invokeMethod<String>('getAllProgress');
    expect(res, isNotNull);
    expect(() => jsonDecode(res!), returnsNormally);
  });

  testWidgets('getDownloadPriority returns a valid JSON array', (tester) async {
    final res = await channel.invokeMethod<String>('getDownloadPriority');
    expect(res, isNotNull);
    final decoded = jsonDecode(res!);
    expect(decoded, isA<List>());
  });

  testWidgets('setDownloadPriority/getDownloadPriority round-trip', (tester) async {
    await channel.invokeMethod<void>(
      'setDownloadPriority',
      {'priorityJson': jsonEncode(['a', 'b'])},
    );
    final res = await channel.invokeMethod<String>('getDownloadPriority');
    expect(res, isNotNull);
    final decoded = (jsonDecode(res!) as List).map((e) => e.toString()).toList();
    expect(decoded, ['a', 'b'],
        reason: 'Kotlin JSON (de)serialization must preserve order and values');
  });

  testWidgets('setMetadataPriority/getMetadataPriority round-trip', (tester) async {
    await channel.invokeMethod<void>(
      'setMetadataPriority',
      {'priorityJson': jsonEncode(['a', 'b'])},
    );
    final res = await channel.invokeMethod<String>('getMetadataPriority');
    expect(res, isNotNull);
    final decoded = (jsonDecode(res!) as List).map((e) => e.toString()).toList();
    expect(decoded, ['a', 'b'],
        reason: 'Kotlin JSON (de)serialization must preserve order and values');
  });
}
