import 'package:flutter/material.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surface2,
    required this.surface3,
    required this.accentSoft,
    required this.accentLine,
    required this.accentInk,
    required this.warn,
    required this.warnSoft,
    required this.warnLine,
    required this.down,
    required this.downSoft,
    required this.muted2,
    required this.mono,
  });

  final Color surface2, surface3, accentSoft, accentLine, accentInk;
  final Color warn, warnSoft, warnLine, down, downSoft, muted2;
  final TextStyle mono;

  static const AppTokens dark = AppTokens(
    surface2: Color(0xFF1C1F23),
    surface3: Color(0xFF252930),
    accentSoft: Color(0xFF10241A),
    accentLine: Color(0xFF1F4D36),
    accentInk: Color(0xFF04150C),
    warn: Color(0xFFE0B341),
    warnSoft: Color(0xFF2A2310),
    warnLine: Color(0xFF4D4022),
    down: Color(0xFFE06A52),
    downSoft: Color(0xFF2A1714),
    muted2: Color(0xFF565C65),
    mono: TextStyle(
      fontFamily: 'monospace',
      fontFeatures: [FontFeature.tabularFigures()],
      letterSpacing: -0.2,
    ),
  );

  @override
  AppTokens copyWith({Color? surface2, Color? surface3, Color? accentSoft, Color? accentLine,
      Color? accentInk, Color? warn, Color? warnSoft, Color? warnLine, Color? down, Color? downSoft,
      Color? muted2, TextStyle? mono}) {
    return AppTokens(
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      accentSoft: accentSoft ?? this.accentSoft,
      accentLine: accentLine ?? this.accentLine,
      accentInk: accentInk ?? this.accentInk,
      warn: warn ?? this.warn,
      warnSoft: warnSoft ?? this.warnSoft,
      warnLine: warnLine ?? this.warnLine,
      down: down ?? this.down,
      downSoft: downSoft ?? this.downSoft,
      muted2: muted2 ?? this.muted2,
      mono: mono ?? this.mono,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      warnLine: Color.lerp(warnLine, other.warnLine, t)!,
      down: Color.lerp(down, other.down, t)!,
      downSoft: Color.lerp(downSoft, other.downSoft, t)!,
      muted2: Color.lerp(muted2, other.muted2, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}
