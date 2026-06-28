import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasources/location_datasource.dart';
import '../../data/repositories/location_repository_impl.dart';
import '../../domain/entities/coordinates.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/location_repository.dart';

/// DI cho feature location.
final locationDataSourceProvider = Provider<LocationDataSource>(
  (ref) => LocationDataSource(ref.watch(permissionServiceProvider)),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepositoryImpl(ref.watch(locationDataSourceProvider)),
);

/// Vị trí hiện tại (1 lần). UI watch provider này; gọi `ref.invalidate` để thử
/// lại sau khi cấp quyền. Ném Failure (qua AsyncError) nếu thất bại.
final currentLocationProvider = FutureProvider<Coordinates>((ref) async {
  final repo = ref.watch(locationRepositoryProvider);
  final result = await repo.getCurrentLocation();
  return result.fold((failure) => throw failure, (coords) => coords);
});

/// Stream vị trí khi di chuyển — dành cho màn hình cần cập nhật liên tục.
final locationStreamProvider = StreamProvider<Coordinates>((ref) {
  return ref.watch(locationRepositoryProvider).watchLocation();
});

/// Tên địa danh hiện tại (reverse geocoding). Null nếu chưa/không xác định
/// được — UI hiển thị fallback, không chặn luồng thời tiết.
final currentPlaceProvider = FutureProvider<Place?>((ref) async {
  final coords = await ref.watch(currentLocationProvider.future);
  final repo = ref.watch(locationRepositoryProvider);
  return repo.getPlace(coords);
});
