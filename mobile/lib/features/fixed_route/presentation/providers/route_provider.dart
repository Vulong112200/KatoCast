import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasources/overpass_datasource.dart';
import '../../data/datasources/route_local_datasource.dart';
import '../../data/repositories/poi_repository_impl.dart';
import '../../domain/entities/poi.dart';
import '../../domain/entities/route_point.dart';
import '../../domain/repositories/poi_repository.dart';

/// Id lộ trình mặc định (Phase này hỗ trợ 1 lộ trình; mở rộng multi-route sau).
const String kDefaultRouteId = 'default';

// --- DI ---
final routeLocalDataSourceProvider = Provider<RouteLocalDataSource>(
  (ref) => RouteLocalDataSource(ref.watch(appDatabaseProvider)),
);

final overpassDataSourceProvider = Provider<OverpassDataSource>(
  (ref) => OverpassDataSource(),
);

final poiRepositoryProvider = Provider<PoiRepository>(
  (ref) => PoiRepositoryImpl(
    ref.watch(routeLocalDataSourceProvider),
    ref.watch(overpassDataSourceProvider),
  ),
);

/// State của màn lộ trình: các điểm + kết quả quét POI + trạng thái.
class RouteState {
  final List<RoutePoint> points;
  final List<Poi> pois;
  final bool scanning;
  final String? error;

  const RouteState({
    this.points = const [],
    this.pois = const [],
    this.scanning = false,
    this.error,
  });

  RouteState copyWith({
    List<RoutePoint>? points,
    List<Poi>? pois,
    bool? scanning,
    String? error,
    bool clearError = false,
  }) {
    return RouteState(
      points: points ?? this.points,
      pois: pois ?? this.pois,
      scanning: scanning ?? this.scanning,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Quản lý lộ trình cố định + quét POI dọc lộ trình.
class RouteController extends StateNotifier<RouteState> {
  final PoiRepository _repo;

  RouteController(this._repo) : super(const RouteState()) {
    _load();
  }

  Future<void> _load() async {
    final points = await _repo.getRoute(kDefaultRouteId);
    state = state.copyWith(points: points);
  }

  /// Thêm 1 điểm vào cuối lộ trình (seq tăng dần) rồi nạp lại.
  Future<void> addPoint(double lat, double lng, {String? label}) async {
    final nextSeq = state.points.isEmpty ? 0 : state.points.last.seq + 1;
    await _repo.addPoint(RoutePoint(
      routeId: kDefaultRouteId,
      latitude: lat,
      longitude: lng,
      seq: nextSeq,
      label: label,
    ));
    await _load();
  }

  /// Xoá toàn bộ lộ trình + kết quả quét.
  Future<void> clear() async {
    await _repo.deleteRoute(kDefaultRouteId);
    state = const RouteState();
  }

  /// Quét POI dọc lộ trình theo loại + bán kính.
  Future<void> scan({
    required int radiusMeters,
    required List<PoiType> types,
  }) async {
    if (state.points.isEmpty) {
      state = state.copyWith(error: 'Hãy thêm ít nhất 1 điểm lộ trình trước.');
      return;
    }
    state = state.copyWith(scanning: true, clearError: true, pois: []);
    try {
      final pois = await _repo.scanPoisAlongRoute(
        kDefaultRouteId,
        radiusMeters: radiusMeters,
        types: types,
      );
      state = state.copyWith(pois: pois, scanning: false);
    } catch (_) {
      state = state.copyWith(
        scanning: false,
        error: 'Không quét được tiện ích. Kiểm tra kết nối mạng rồi thử lại.',
      );
    }
  }
}

final routeControllerProvider =
    StateNotifierProvider<RouteController, RouteState>(
  (ref) => RouteController(ref.watch(poiRepositoryProvider)),
);
