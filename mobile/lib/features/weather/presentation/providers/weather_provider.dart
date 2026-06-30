import 'package:connectivity_plus/connectivity_plus.dart';
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

/// Thời tiết tại vị trí hiện tại — **stale-while-revalidate**.
///
/// Mở app: phát ngay cache hiện có (UI hiển thị tức thì, không kẹt "Đang lấy
/// dữ liệu"), rồi mới gọi API làm mới NẾU cache thiếu hoặc đã quá ngưỡng
/// (`needsRevalidate`, 15' — khớp chu kỳ nền). Cache còn tươi → bỏ qua gọi API
/// (tiết kiệm quota). Fetch lỗi mà đã có cache → giữ cache, không báo lỗi.
///
/// `ref.invalidate(weatherProvider)` để refresh; lỗi vị trí/quyền nổi lên qua
/// AsyncError để UI hiển thị đúng widget.
final weatherProvider = StreamProvider<WeatherData>((ref) async* {
  final Coordinates coords = await ref.watch(currentLocationProvider.future);
  final repo = ref.watch(weatherRepositoryProvider);

  // 1. Cache trước (nếu có) → vẽ ngay.
  final cached = await repo.getCachedWeather(coords);
  if (cached != null) yield cached;

  // 2. Làm mới khi thiếu cache hoặc cache đã quá ngưỡng.
  if (cached == null || cached.needsRevalidate) {
    final result = await repo.getWeather(coords);
    yield* result.fold(
      (failure) async* {
        // Không có gì để hiện → báo lỗi; còn cache thì giữ nguyên (im lặng).
        if (cached == null) throw failure;
      },
      (data) async* {
        yield data;
      },
    );
  }
});

/// Trạng thái online/offline theo thời gian thực (connectivity_plus). Dùng để
/// badge "dữ liệu cũ" nói đúng: thật sự offline vs đang làm mới. Lưu ý
/// connectivity_plus chỉ phản ánh interface mạng, không kiểm tra reachability —
/// đủ để phân biệt "tắt mạng" với "có mạng".
final connectivityStatusProvider = StreamProvider<bool>((ref) async* {
  final conn = ref.watch(connectivityProvider);
  bool online(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  yield online(await conn.checkConnectivity());
  yield* conn.onConnectivityChanged.map(online);
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
