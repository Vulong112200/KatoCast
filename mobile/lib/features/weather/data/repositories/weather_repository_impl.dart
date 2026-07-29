import 'package:dartz/dartz.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/diagnostics/app_log.dart';
import '../../../../core/diagnostics/log_entry.dart';
import '../../../../core/diagnostics/log_tags.dart';
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

  /// Lớp gọi (xem `LogSource`) — chỉ để nhật ký ghi rõ ai đã gọi API.
  final String logSource;

  WeatherRepositoryImpl(
    this._remote,
    this._local,
    this._network, {
    this.logSource = LogSource.ui,
  });

  @override
  Future<Either<Failure, WeatherData>> getWeather(
    Coordinates coords, {
    bool forceRefresh = false,
  }) async {
    final online = await _network.isOnline;

    // Nếu offline → đi thẳng vào cache.
    if (!online) {
      await AppLog.w(
        logSource,
        LogTags.fetch,
        'đang OFFLINE → dùng cache nếu có',
      );
      return _fromCacheOr(coords, const NetworkFailure());
    }

    final startedAt = DateTime.now();
    try {
      final json = await _remote.fetchOneCall(coords);
      final now = DateTime.now();
      await _local.cache(coords, json, now);
      await AppLog.i(
        logSource,
        LogTags.fetch,
        'gọi API OK (3 endpoint One Call 4.0)',
        data: {'mất': '${now.difference(startedAt).inMilliseconds}ms'},
      );
      return Right(WeatherMapper.fromOneCallJson(json, fetchedAt: now));
    } on NetworkException catch (e) {
      await _logFetchFailure('lỗi mạng', e, startedAt);
      return _fromCacheOr(coords, const NetworkFailure());
    } on ServerException catch (e) {
      await _logFetchFailure('lỗi máy chủ (${e.statusCode})', e, startedAt);
      // Lỗi server: vẫn thử cache (nếu có) để app dùng được, nếu không trả lỗi.
      return _fromCacheOr(
        coords,
        ServerFailure(e.message, statusCode: e.statusCode),
      );
    } catch (e) {
      await _logFetchFailure('lỗi không lường trước', e, startedAt);
      return _fromCacheOr(coords, const UnexpectedFailure());
    }
  }

  Future<void> _logFetchFailure(
    String what,
    Object error,
    DateTime startedAt,
  ) =>
      AppLog.w(
        logSource,
        LogTags.fetch,
        'gọi API THẤT BẠI: $what → thử cache',
        data: {
          'mất': '${DateTime.now().difference(startedAt).inMilliseconds}ms',
          'err': error.toString(),
        },
      );

  @override
  Future<WeatherData?> getCachedWeather(Coordinates coords) async {
    final cached = await _local.read(coords);
    if (cached == null) return null;
    final (json, fetchedAt) = cached;
    return WeatherMapper.fromOneCallJson(json, fetchedAt: fetchedAt);
  }

  /// Đọc cache; trả [fallbackFailure] nếu không có.
  Future<Either<Failure, WeatherData>> _fromCacheOr(
    Coordinates coords,
    Failure fallbackFailure,
  ) async {
    final cached = await _local.read(coords);
    if (cached == null) {
      await AppLog.w(
        logSource,
        LogTags.fetch,
        'không có cache cho toạ độ này → trả lỗi',
      );
      return Left(fallbackFailure);
    }
    final (json, fetchedAt) = cached;
    await AppLog.w(
      logSource,
      LogTags.fetch,
      'dùng CACHE CŨ thay cho dữ liệu tươi (fromCacheFallback)',
      data: {'lấy lúc': fetchedAt.toLocal().toString()},
    );
    // Đánh dấu fromCacheFallback: đây là cache CŨ trả về vì fetch remote lỗi,
    // KHÔNG phải dữ liệu tươi — caller cần biết để báo trung thực.
    return Right(WeatherMapper.fromOneCallJson(
      json,
      fetchedAt: fetchedAt,
      fromCacheFallback: true,
    ));
  }
}

extension WeatherFreshness on WeatherData {
  /// Tuổi của dữ liệu cache.
  Duration get age => DateTime.now().difference(fetchedAt);

  /// Cache đã "cũ" để hiển thị badge nhắc người dùng (ngưỡng rộng hơn).
  bool get isStale => age.inMinutes > AppConfig.cacheFreshnessMinutes;

  /// Có cần gọi API làm mới khi mở app không (ngưỡng khớp chu kỳ nền 15').
  bool get needsRevalidate =>
      age.inMinutes >= AppConfig.weatherRevalidateMinutes;
}
