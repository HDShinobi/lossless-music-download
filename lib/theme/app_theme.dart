import 'package:flutter/material.dart';

const kAccent = Color(0xFF1DB954);   // emerald (v1 lineage)
const kGround = Color(0xFF0E0F11);   // graphite

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
  ).copyWith(primary: kAccent, surface: kGround);
  return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: kGround);
}
