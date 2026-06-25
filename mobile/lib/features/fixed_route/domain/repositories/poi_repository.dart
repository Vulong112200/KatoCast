import '../entities/poi.dart';
import '../entities/route_point.dart';

/// MODULE 2 (Phase 2) — Quét tiện ích dọc lộ trình cố định.
///
/// Phần LƯU TRỮ lộ trình (CRUD route points) đã hoạt động đầy đủ qua
/// [RouteLocalDataSource]. Phần QUÉT POI ([scanPoisAlongRoute]) là stub —
/// kiến trúc đã sẵn để cắm Google Places API sau.
abstract class PoiRepository {
  // --- Lưu trữ lộ trình cố định (dùng được ngay) ---
  Future<List<RoutePoint>> getRoute(String routeId);
  Future<int> addPoint(RoutePoint point);
  Future<void> deleteRoute(String routeId);

  // --- Quét POI (Phase 2 — stub) ---
  /// Quét các tiện ích thuộc [types] nằm trong [radiusMeters] quanh các điểm
  /// của lộ trình [routeId].
  Future<List<Poi>> scanPoisAlongRoute(
    String routeId, {
    required int radiusMeters,
    required List<PoiType> types,
  });
}
