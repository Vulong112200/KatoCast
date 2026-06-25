import '../../domain/entities/poi.dart';
import '../../domain/entities/route_point.dart';
import '../../domain/repositories/poi_repository.dart';
import '../datasources/route_local_datasource.dart';

/// Triển khai PoiRepository.
/// - CRUD lộ trình: ủy quyền cho [RouteLocalDataSource] (hoạt động đầy đủ).
/// - Quét POI: STUB (Phase 2).
class PoiRepositoryStub implements PoiRepository {
  final RouteLocalDataSource _local;
  const PoiRepositoryStub(this._local);

  @override
  Future<List<RoutePoint>> getRoute(String routeId) => _local.getRoute(routeId);

  @override
  Future<int> addPoint(RoutePoint point) => _local.addPoint(point);

  @override
  Future<void> deleteRoute(String routeId) => _local.deleteRoute(routeId);

  @override
  Future<List<Poi>> scanPoisAlongRoute(
    String routeId, {
    required int radiusMeters,
    required List<PoiType> types,
  }) async {
    // TODO(Phase 2): với mỗi điểm trong getRoute(routeId), gọi Google Places
    // Nearby Search (type = restaurant/gas_station/cafe/supermarket) trong bán
    // kính radiusMeters; gộp & khử trùng lặp; tính distanceToRouteMeters (vd
    // khoảng cách điểm→đoạn thẳng lộ trình) rồi lọc các POI nằm sát lộ trình.
    throw UnimplementedError(
      'scanPoisAlongRoute chưa triển khai (Phase 2 — Google Places API).',
    );
  }
}
