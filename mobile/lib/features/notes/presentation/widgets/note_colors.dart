import 'package:flutter/material.dart';

/// Bảng màu ghi chú (pastel). Index 0 = "mặc định" — dùng màu surface theme.
const List<Color> kNoteColors = [
  Colors.transparent, // 0: mặc định theo theme
  Color(0xFFFFF59D), // vàng
  Color(0xFFFFCC80), // cam
  Color(0xFFEF9A9A), // đỏ hồng
  Color(0xFFF48FB1), // hồng
  Color(0xFFCE93D8), // tím
  Color(0xFF90CAF9), // xanh dương
  Color(0xFFA5D6A7), // xanh lá
];

/// Màu nền card cho note: hoà với theme để đọc được ở cả dark mode.
Color noteCardColor(BuildContext context, int colorIndex) {
  final scheme = Theme.of(context).colorScheme;
  if (colorIndex <= 0 || colorIndex >= kNoteColors.length) {
    return scheme.surfaceContainerHighest;
  }
  final base = kNoteColors[colorIndex];
  // Dark mode: phủ màu note lên surface với alpha thấp cho dễ đọc chữ.
  return Color.alphaBlend(
    base.withValues(alpha: Theme.of(context).brightness == Brightness.dark
        ? 0.28
        : 0.55),
    scheme.surfaceContainerHighest,
  );
}
