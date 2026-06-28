import 'coordinates.dart';

/// Thông tin địa danh đọc được từ reverse geocoding (toạ độ -> tên).
/// Tất cả trường text đều optional vì reverse geocoding có thể trả thiếu.
class Place {
  final Coordinates coordinates;

  /// Phường/xã (ví dụ "Phường Bến Nghé").
  final String? subLocality;

  /// Quận/huyện hoặc thành phố nhỏ (ví dụ "Quận 1").
  final String? locality;

  /// Tỉnh/thành phố (ví dụ "Hồ Chí Minh").
  final String? administrativeArea;

  final String? country;

  const Place({
    required this.coordinates,
    this.subLocality,
    this.locality,
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
}
