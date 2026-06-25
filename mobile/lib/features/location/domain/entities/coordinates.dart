/// Toạ độ địa lý — entity thuần domain (không phụ thuộc geolocator).
class Coordinates {
  final double latitude;
  final double longitude;

  const Coordinates({required this.latitude, required this.longitude});

  /// Khoá cache làm tròn 2 chữ số (~1.1km) để gom các lần định vị gần nhau,
  /// tránh tạo quá nhiều bản ghi cache.
  String get cacheKey =>
      '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';

  @override
  String toString() => 'Coordinates($latitude, $longitude)';
}
