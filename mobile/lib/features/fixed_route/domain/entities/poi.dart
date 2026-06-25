/// Loại tiện ích cần quét dọc lộ trình.
enum PoiType { restaurant, gasStation, cafe, supermarket }

/// Một điểm tiện ích (Point Of Interest) nằm trên/sát lộ trình cố định.
class Poi {
  final String name;
  final PoiType type;
  final double latitude;
  final double longitude;

  /// Khoảng cách (mét) từ POI tới lộ trình gần nhất.
  final double distanceToRouteMeters;

  const Poi({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceToRouteMeters,
  });
}
