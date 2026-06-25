import 'package:dartz/dartz.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../../location/domain/entities/coordinates.dart';
import '../../domain/entities/weather.dart';
import '../../domain/repositories/weather_repository.dart';
import '../datasources/weather_local_datasource.dart';
import '../datasources/weather_remote_datasource.dart';
import '../models/weather_model.dart';

/// Triển khai offline-first:
/// 1. Còn online → gọi remote, lưu cache, trả dữ liệu tươi.
/// 2. Offline (hoặc remote lỗi) → fallback cache; rỗng thì trả CacheFailure.
class WeatherRepositoryImpl implements WeatherRepository {
  final WeatherRemoteDataSource _remote;
  final WeatherLocalDataSource _local;
  final NetworkInfo _network;

  WeatherRepositoryImpl(this._remote, this._local, this._network);

  @override
  Future<Either<Failure, WeatherData>> getWeather(
    Coordinates coords, {
    bool forceRefresh = false,
  }) async {
    final online = await _network.isOnline;

    // Nếu offline → đi thẳng vào cache.
    if (!online) {
      return _fromCacheOr(coords, const NetworkFailure());
    }

    try {
      final json = await _remote.fetchOneCall(coords);
      final now = DateTime.now();
      await _local.cache(coords, json, now);
      return Right(WeatherMapper.fromOneCallJson(json, fetchedAt: now));
    } on NetworkException {
      return _fromCacheOr(coords, const NetworkFailure());
    } on ServerException catch (e) {
      // Lỗi server: vẫn thử cache (nếu có) để app dùng được, nếu không trả lỗi.
      return _fromCacheOr(
        coords,
        ServerFailure(e.message, statusCode: e.statusCode),
      );
    } catch (_) {
      return _fromCacheOr(coords, const UnexpectedFailure());
    }
  }

  /// Đọc cache; trả [fallbackFailure] nếu không có.
  Future<Either<Failure, WeatherData>> _fromCacheOr(
    Coordinates coords,
    Failure fallbackFailure,
  ) async {
    final cached = await _local.read(coords);
    if (cached == null) return Left(fallbackFailure);
    final (json, fetchedAt) = cached;
    return Right(WeatherMapper.fromOneCallJson(json, fetchedAt: fetchedAt));
  }
}

extension WeatherFreshness on WeatherData {
  /// Cache còn "tươi" không (để UI quyết định hiển thị badge offline/cũ).
  bool get isStale =>
      DateTime.now().difference(fetchedAt).inMinutes >
      AppConfig.cacheFreshnessMinutes;
}
