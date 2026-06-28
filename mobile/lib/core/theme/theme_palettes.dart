import 'package:flutter/material.dart';

/// Một bảng màu chọn sẵn cho người dùng (seed của Material 3).
class AppPalette {
  final String id;
  final String label;
  final Color seed;

  const AppPalette({required this.id, required this.label, required this.seed});
}

/// Danh sách bảng màu người dùng có thể chọn trong Settings.
const List<AppPalette> kAppPalettes = [
  AppPalette(id: 'blue', label: 'Xanh dương', seed: Color(0xFF2E6FB7)),
  AppPalette(id: 'teal', label: 'Xanh ngọc', seed: Color(0xFF009688)),
  AppPalette(id: 'green', label: 'Lục', seed: Color(0xFF2E7D32)),
  AppPalette(id: 'orange', label: 'Cam', seed: Color(0xFFEF6C00)),
  AppPalette(id: 'purple', label: 'Tím', seed: Color(0xFF6A4CAF)),
  AppPalette(id: 'pink', label: 'Hồng', seed: Color(0xFFC2185B)),
];

/// Bảng màu mặc định (khớp tông logo).
const String kDefaultPaletteId = 'blue';

/// Tra cứu seed theo id; fallback về bảng màu mặc định.
Color seedForPaletteId(String id) {
  return kAppPalettes
      .firstWhere(
        (p) => p.id == id,
        orElse: () => kAppPalettes.first,
      )
      .seed;
}
