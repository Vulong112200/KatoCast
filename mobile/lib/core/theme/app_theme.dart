import 'package:flutter/material.dart';

/// Dựng ThemeData nhất quán cho toàn app từ một [seed] màu + [brightness].
/// Dùng chung cho light/dark và mọi nguồn seed (palette / weather / dynamic).
ThemeData buildAppTheme({
  required Color seed,
  required Brightness brightness,
  ColorScheme? dynamicScheme,
}) {
  final scheme = dynamicScheme ??
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
  );
}
