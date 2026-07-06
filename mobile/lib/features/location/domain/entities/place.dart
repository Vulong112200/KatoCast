import 'coordinates.dart';

/// Thông tin địa danh đọc được từ reverse geocoding (toạ độ -> tên).
/// Tất cả trường text đều optional vì reverse geocoding có thể trả thiếu.
class Place {
  final Coordinates coordinates;

  /// Đường/phố (ví dụ "Đường Lê Lợi"), có thể kèm số nhà. Thường chỉ có khi
  /// reverse geocoding qua Nominatim (plugin nền tảng ở VN hay trả null).
  final String? thoroughfare;

  /// Phường/xã (ví dụ "Phường Bến Nghé").
  final String? subLocality;

  /// Quận/huyện hoặc thành phố nhỏ (ví dụ "Quận 1").
  final String? locality;

  /// Quận/huyện cấp trên locality (Placemark.subAdministrativeArea) — bổ sung
  /// khi locality trống để nhãn đầy đủ hơn (ví dụ "Thành phố Thủ Đức").
  final String? subAdministrativeArea;

  /// Tỉnh/thành phố (ví dụ "Hồ Chí Minh").
  final String? administrativeArea;

  final String? country;

  const Place({
    required this.coordinates,
    this.thoroughfare,
    this.subLocality,
    this.locality,
    this.subAdministrativeArea,
    this.administrativeArea,
    this.country,
  });

  /// Nhãn ngắn gọn hiển thị trên AppBar.
  /// Ưu tiên: phường, quận → tỉnh/thành; fallback về toạ độ rút gọn.
  String get shortLabel {
    final parts = <String>[];
    final primary = subLocality?.trim().isNotEmpty == true
        ? subLocality!.trim()
        : (locality?.trim().isNotEmpty == true ? locality!.trim() : null);
    if (primary != null) parts.add(primary);

    final region = administrativeArea?.trim();
    if (region != null && region.isNotEmpty && region != primary) {
      parts.add(region);
    }

    if (parts.isEmpty) {
      return '${coordinates.latitude.toStringAsFixed(3)}, '
          '${coordinates.longitude.toStringAsFixed(3)}';
    }
    return parts.join(', ');
  }

  /// Nhãn ĐẦY ĐỦ hiển thị trong thân màn hình (không bị cắt): gộp phường/xã →
  /// quận/huyện → tỉnh/thành, bỏ các phần trùng/rỗng. Fallback về toạ độ nếu
  /// không có tên nào.
  String get fullLabel {
    final ordered = <String?>[
      thoroughfare,
      subLocality,
      locality,
      subAdministrativeArea,
      administrativeArea,
    ];
    final parts = <String>[];
    for (final raw in ordered) {
      final v = raw?.trim();
      if (v == null || v.isEmpty) continue;
      // Bỏ trùng lặp (không phân biệt hoa/thường) để tránh "Quận 1, Quận 1".
      if (parts.any((p) => p.toLowerCase() == v.toLowerCase())) continue;
      parts.add(v);
    }
    if (parts.isEmpty) {
      return '${coordinates.latitude.toStringAsFixed(3)}, '
          '${coordinates.longitude.toStringAsFixed(3)}';
    }
    return parts.join(', ');
  }
}
