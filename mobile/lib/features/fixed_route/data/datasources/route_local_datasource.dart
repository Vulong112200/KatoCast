import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/route_point.dart';

/// CRUD lộ trình cố định trong Drift (bảng fixed_route_points). HOẠT ĐỘNG ĐẦY ĐỦ.
class RouteLocalDataSource {
  final AppDatabase _db;
  RouteLocalDataSource(this._db);

  Future<List<RoutePoint>> getRoute(String routeId) async {
    final rows = await (_db.select(_db.fixedRoutePoints)
          ..where((t) => t.routeId.equals(routeId))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    return rows
        .map((r) => RoutePoint(
              id: r.id,
              routeId: r.routeId,
              latitude: r.latitude,
              longitude: r.longitude,
              seq: r.seq,
              label: r.label,
            ))
        .toList();
  }

  Future<int> addPoint(RoutePoint p) {
    return _db.into(_db.fixedRoutePoints).insert(
          FixedRoutePointsCompanion.insert(
            routeId: p.routeId,
            latitude: p.latitude,
            longitude: p.longitude,
            seq: p.seq,
            label: Value(p.label),
          ),
        );
  }

  Future<void> deleteRoute(String routeId) async {
    await (_db.delete(_db.fixedRoutePoints)
          ..where((t) => t.routeId.equals(routeId)))
        .go();
  }
}
