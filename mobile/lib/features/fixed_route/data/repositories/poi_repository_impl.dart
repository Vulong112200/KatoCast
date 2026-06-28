import 'package:geolocator/geolocator.dart';

import '../../domain/entities/poi.dart';
import '../../domain/entities/route_point.dart';
import '../../domain/repositories/poi_repository.dart';
import '../datasources/overpass_datasource.dart';
import '../datasources/route_local_datasource.dart';

/// Triển khai PoiRepository:
/// - CRUD lộ trình: ủy quyền cho [RouteLocalDataSource] (Drift).
/// - Quét POI: [OverpassDataSource] (OpenStreetMap, miễn phí) → tính khoảng
///   cách tới lộ trình, khử trùng, lọc trong bán kính, sắp xếp theo độ gần.
class PoiRepositoryImpl implements PoiRepository {
  final RouteLocalDataSource _local;
  final OverpassDataSource _overpass;

  const PoiRepositoryImpl(this._local, this._overpass);

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
    final route = await _local.getRoute(routeId);
    if (route.isEmpty) return [];

    final raw = await _overpass.fetchPois(
      route,
      radiusMeters: radiusMeters,
      types: types,
    );

    // Khử trùng (cùng toạ độ làm tròn ~11m + cùng loại) và tính khoảng cách
    // tới điểm gần nhất trên lộ trình.
    final seen = <String>{};
    final result = <Poi>[];
    for (final p in raw) {
      final key = '${p.type.index}:${p.latitude.toStringAsFixed(4)},'
          '${p.longitude.toStringAsFixed(4)}';
      if (!seen.add(key)) continue;

      final dist = _distanceToRoute(p.latitude, p.longitude, route);
      if (dist > radiusMeters) continue; // lọc POI nằm ngoài bán kính.

      result.add(Poi(
        name: p.name,
        type: p.type,
        latitude: p.latitude,
        longitude: p.longitude,
        distanceToRouteMeters: dist,
      ));
    }

    result.sort(
      (a, b) => a.distanceToRouteMeters.compareTo(b.distanceToRouteMeters),
    );
    return result;
  }

  /// Khoảng cách (mét) tới điểm gần nhất trên lộ trình. Xấp xỉ đủ tốt khi các
  /// điểm lộ trình đủ dày; Overpass đã lọc quanh từng điểm nên sai số nhỏ.
  double _distanceToRoute(double lat, double lng, List<RoutePoint> route) {
    var min = double.infinity;
    for (final pt in route) {
      final d = Geolocator.distanceBetween(lat, lng, pt.latitude, pt.longitude);
      if (d < min) min = d;
    }
    return min;
  }
}
