import 'package:dio/dio.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../location/domain/entities/coordinates.dart';

/// Gọi One Call **4.0** và CHUẨN HOÁ về shape gộp (current + minutely + hourly)
/// để `WeatherMapper` (vốn parse cấu trúc 3.0) dùng lại không đổi.
///
/// 4.0 tách dữ liệu thành các endpoint timeline riêng:
/// - `/onecall/current`       → thời tiết hiện tại (data[0])
/// - `/onecall/timeline/15min`→ nowcast 15' (thay cho `minutely` 1' của 3.0)
/// - `/onecall/timeline/1h`   → dự báo theo giờ
/// Adapter ở tầng data: gọi song song 3 endpoint, gộp lại, trả Map shape 3.0.
class WeatherRemoteDataSource {
  final ApiClient _client;
  WeatherRemoteDataSource(this._client);

  Future<Map<String, dynamic>> fetchOneCall(Coordinates coords) async {
    if (!AppConfig.hasApiKey) {
      throw const ServerException(
        'Chưa cấu hình OWM_API_KEY. Chạy với --dart-define=OWM_API_KEY=<key>.',
      );
    }

    final query = {
      'lat': coords.latitude,
      'lon': coords.longitude,
      'units': AppConfig.owmUnits,
      'lang': AppConfig.owmLang,
      'appid': AppConfig.owmApiKey,
    };

    try {
      // Gọi song song 3 endpoint để giảm độ trễ.
      final results = await Future.wait([
        _getData('/onecall/current', query),
        _getData('/onecall/timeline/15min', query),
        _getData('/onecall/timeline/1h', query),
      ]);

      final currentList = results[0];
      final min15 = results[1];
      final hourly = results[2];

      if (currentList.isEmpty) {
        throw const ServerException('Thiếu dữ liệu thời tiết hiện tại (4.0).');
      }

      // --- Chuẩn hoá về shape gộp giống One Call 3.0 ---
      return {
        // current: data[0] của 4.0 đã có temp/feels_like/humidity/uvi/clouds/
        // wind_speed/weather[]/rain{1h}/dt — khớp WeatherMapper._current.
        'current': currentList.first,
        // minutely: mỗi mốc 15' → {dt, precipitation(mm/h) từ rain.1h, pop}.
        // pop của nowcast 15' nhạy hơn hourly.pop → cột giờ gần dùng số này.
        'minutely': [
          for (final r in min15)
            {'dt': r['dt'], 'precipitation': _rain1h(r['rain']), 'pop': r['pop']},
        ],
        // hourly: giữ nguyên các trường WeatherMapper._hourlyList cần.
        'hourly': hourly,
      };
    } on DioException catch (e) {
      final mapped = e.error;
      if (mapped is ServerException || mapped is NetworkException) {
        throw mapped as Object;
      }
      throw const NetworkException();
    }
  }

  /// GET 1 endpoint 4.0, trả `data` (List các bản ghi).
  Future<List<Map<String, dynamic>>> _getData(
    String path,
    Map<String, dynamic> query,
  ) async {
    final res = await _client.dio.get<Map<String, dynamic>>(path,
        queryParameters: query);
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Lấy lượng mưa (mm/h) từ field rain {"1h": x}; 0 nếu vắng.
  static double _rain1h(dynamic rain) {
    if (rain is num) return rain.toDouble();
    if (rain is Map && rain['1h'] is num) return (rain['1h'] as num).toDouble();
    return 0.0;
  }
}
