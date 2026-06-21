import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';

void main() {
  test('AppTokens.dark holds the locked brand hexes', () {
    const t = AppTokens.dark;
    expect(t.surface2, const Color(0xFF1C1F23));
    expect(t.surface3, const Color(0xFF252930));
    expect(t.accentSoft, const Color(0xFF10241A));
    expect(t.accentLine, const Color(0xFF1F4D36));
    expect(t.accentInk, const Color(0xFF04150C));
    expect(t.warn, const Color(0xFFE0B341));
    expect(t.down, const Color(0xFFE06A52));
    expect(t.muted2, const Color(0xFF565C65));
  });

  test('lerp returns an AppTokens (identity at t=0)', () {
    const t = AppTokens.dark;
    final l = t.lerp(t, 0) as AppTokens;
    expect(l.accentSoft, t.accentSoft);
  });
}
