import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../location/domain/entities/coordinates.dart';
import '../entities/weather.dart';

/// Hợp đồng Repository cho thời tiết.
///
/// `forceRefresh=false`: ưu tiên cache còn tươi (tiết kiệm gọi API & pin).
/// Khi offline tự fallback cache. Sau này nhúng backend FastAPI chỉ cần thay
/// implementation, UI/usecase không đổi.
abstract class WeatherRepository {
  Future<Either<Failure, WeatherData>> getWeather(
    Coordinates coords, {
    bool forceRefresh = false,
  });

  /// Đọc thẳng cache (không gọi mạng). null nếu chưa có cache cho toạ độ này.
  /// Dùng để hiển thị tức thì khi mở app (stale-while-revalidate).
  Future<WeatherData?> getCachedWeather(Coordinates coords);
}
