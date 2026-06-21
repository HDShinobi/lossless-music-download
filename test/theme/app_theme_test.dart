import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';

void main() {
  test('appTheme wires brand ColorScheme roles + AppTokens', () {
    final th = appTheme();
    expect(th.colorScheme.primary, const Color(0xFF1DB954));
    expect(th.colorScheme.surface, const Color(0xFF0E0F11));
    // NavigationBar indicator must be crisp accent-soft, not auto-muted:
    expect(th.colorScheme.secondaryContainer, const Color(0xFF10241A));
    expect(th.colorScheme.onPrimary, const Color(0xFF04150C));
    expect(th.extension<AppTokens>(), isNotNull);
    expect(th.brightness, Brightness.dark);
  });
}
