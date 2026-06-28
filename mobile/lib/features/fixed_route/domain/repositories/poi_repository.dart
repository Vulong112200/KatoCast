import '../entities/poi.dart';
import '../entities/route_point.dart';

/// MODULE 2 — Quét tiện ích dọc lộ trình cố định.
///
/// Phần LƯU TRỮ lộ trình (CRUD route points) qua [RouteLocalDataSource] (Drift).
/// Phần QUÉT POI ([scanPoisAlongRoute]) dùng OpenStreetMap/Overpass (miễn phí).
abstract class PoiRepository {
  // --- Lưu trữ lộ trình cố định ---
  Future<List<RoutePoint>> getRoute(String routeId);
  Future<int> addPoint(RoutePoint point);
  Future<void> deleteRoute(String routeId);

  // --- Quét POI (Overpass/OSM) ---
  /// Quét các tiện ích thuộc [types] nằm trong [radiusMeters] quanh các điểm
  /// của lộ trình [routeId].
  Future<List<Poi>> scanPoisAlongRoute(
    String routeId, {
    required int radiusMeters,
    required List<PoiType> types,
  });
}
