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
}
