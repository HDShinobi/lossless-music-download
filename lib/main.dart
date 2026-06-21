import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const App());

const _channel = MethodChannel('xyz.losslessmusic/native');

Future<String> nativePing() async =>
    await _channel.invokeMethod<String>('ping') ?? 'null';

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: FutureBuilder<String>(
              future: nativePing(),
              builder: (c, s) => Text('native: ${s.data ?? "..."}',
                  key: const Key('ping_text')),
            ),
          ),
        ),
      );
}
