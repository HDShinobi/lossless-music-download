import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';

void main() => runApp(const App());

const _channel = MethodChannel('xyz.losslessmusic/native');

Future<String> nativePing() async =>
    await _channel.invokeMethod<String>('ping') ?? 'null';

Future<String> downloadProgress() async =>
    await _channel.invokeMethod<String>('getDownloadProgress') ?? 'null';

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FutureBuilder<String>(
                  future: nativePing(),
                  builder: (c, s) => Text('native: ${s.data ?? "..."}',
                      key: const Key('ping_text')),
                ),
                FutureBuilder<String>(
                  future: downloadProgress(),
                  builder: (c, s) => Text('progress: ${s.data ?? "..."}',
                      key: const Key('progress_text')),
                ),
              ],
            ),
          ),
        ),
      );
}
