import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../location/domain/entities/coordinates.dart';
import '../../../location/presentation/providers/location_provider.dart';
import '../../data/datasources/weather_local_datasource.dart';
import '../../data/datasources/weather_remote_datasource.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../domain/entities/rain_status.dart';
import '../../domain/entities/weather.dart';
import '../../domain/entities/weather_condition.dart';
import '../../domain/repositories/weather_repository.dart';
import '../../domain/usecases/analyze_rain.dart';

/// DI cho feature weather.
final weatherRemoteDataSourceProvider = Provider<WeatherRemoteDataSource>(
  (ref) => WeatherRemoteDataSource(ref.watch(apiClientProvider)),
);

final weatherLocalDataSourceProvider = Provider<WeatherLocalDataSource>(
  (ref) => WeatherLocalDataSource(ref.watch(appDatabaseProvider)),
);

final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => WeatherRepositoryImpl(
    ref.watch(weatherRemoteDataSourceProvider),
    ref.watch(weatherLocalDataSourceProvider),
    ref.watch(networkInfoProvider),
  ),
);

/// Thời tiết tại vị trí hiện tại.
///
/// Chuỗi phụ thuộc: currentLocation → weatherRepository.getWeather.
/// `ref.invalidate(weatherProvider)` để refresh; nếu vị trí lỗi/quyền bị từ
/// chối, lỗi nổi lên qua AsyncError để UI hiển thị đúng widget.
final weatherProvider = FutureProvider<WeatherData>((ref) async {
  final Coordinates coords = await ref.watch(currentLocationProvider.future);
  final repo = ref.watch(weatherRepositoryProvider);
  final result = await repo.getWeather(coords);
  return result.fold((failure) => throw failure, (data) => data);
});

/// Trạng thái mưa suy ra từ dữ liệu thời tiết — dùng cho banner cảnh báo trong UI.
final rainStatusProvider = Provider<RainStatus?>((ref) {
  final async = ref.watch(weatherProvider);
  return async.maybeWhen(
    data: (data) => const AnalyzeRain().call(data),
    orElse: () => null,
  );
});

/// Phân loại tình hình thời tiết hiện tại (nắng/mây/mưa/bão) — hiển thị trên UI.
final weatherConditionProvider = Provider<WeatherCondition?>((ref) {
  final async = ref.watch(weatherProvider);
  return async.maybeWhen(
    data: (data) => WeatherCondition.classify(
      data.current.conditionId,
      rainMmH: data.current.rain1h,
    ),
    orElse: () => null,
  );
});
