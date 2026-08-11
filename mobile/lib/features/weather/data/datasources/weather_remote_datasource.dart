import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

      return normalizeOneCall(
        current: currentList.first,
        min15: min15,
        hourly: hourly,
      );
    } on DioException catch (e) {
      final mapped = e.error;
      if (mapped is ServerException || mapped is NetworkException) {
        throw mapped as Object;
      }
      throw const NetworkException();
    }
  }

  /// Gộp 3 payload của 4.0 về shape giống One Call 3.0 mà `WeatherMapper` hiểu.
  ///
  /// Tách thành hàm THUẦN để test được bằng payload thật, không cần mạng —
  /// chính khâu này từng hỏng âm thầm suốt nhiều tuần mà không test nào chạm tới.
  @visibleForTesting
  static Map<String, dynamic> normalizeOneCall({
    required Map<String, dynamic> current,
    required List<Map<String, dynamic>> min15,
    required List<Map<String, dynamic>> hourly,
  }) {
    return {
      // current: data[0] của 4.0 đã có temp/feels_like/humidity/uvi/clouds/
      // wind_speed/weather[]/rain{1h}/dt — khớp WeatherMapper._current.
      'current': current,
      // minutely: mỗi mốc 15' → {dt, precipitation(mm/h), pop}.
      //
      // ⚠️ KHÔNG đọc `rain` ở đây: endpoint `/timeline/15min` của 4.0 **không
      // bao giờ** trả trường `rain`, kể cả khi đang mưa to. Xác minh bằng API
      // thật (11/08/2026): Manila `current` id=502 `rain.1h`=6.1 mm nhưng
      // 0/50 bản ghi 15' có `rain`; Mumbai (id=501) y hệt. Nó diễn đạt mưa qua
      // `pop` + `weather[].id`. (Ngược lại `/timeline/1h` CÓ `rain` — 20/20.)
      //
      // Bản cũ đọc `rain` nên chuỗi nowcast bị ghim cứng 0.0 → nhật ký thật
      // ghi `nowcast bây giờ = 0.00 mm/h` và `pha = dry` ở **168/168** chu kỳ
      // suốt 2 ngày, kể cả 37 chu kỳ mà `current` đang báo mã 500 kèm lượng
      // mưa đo được. Vì nowcast vừa là nguồn CHÍNH để biết "đang mưa", vừa có
      // quyền PHỦ QUYẾT quan trắc (`nowcastSawNoRainAtAll`), app hoá ra mù hẳn
      // với mưa nhỏ — đúng ca 10/08 18:03 người dùng đi đường bị mưa mà app im.
      'minutely': [
        for (final r in min15)
          {
            'dt': r['dt'],
            'precipitation': precipFromCondition(r['weather']),
            'pop': r['pop'],
          },
      ],
      // hourly: giữ nguyên các trường WeatherMapper._hourlyList cần.
      'hourly': hourly,
    };
  }

  /// GET 1 endpoint 4.0, trả `data` (List các bản ghi).
  Future<List<Map<String, dynamic>>> _getData(
    String path,
    Map<String, dynamic> query,
  ) async {
    final res = await _client.dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
    );
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Suy lượng mưa ĐẠI DIỆN (mm/h) cho một mốc nowcast 15' từ `weather[0].id`.
  ///
  /// Nowcast 4.0 KHÔNG có số milimét (xem ghi chú ở [fetchOneCall]) nên đây là
  /// cách duy nhất để chuỗi `minutely` mang được tín hiệu mưa. Các giá trị chọn
  /// theo đúng dải phân loại cường độ mà app đang dùng ở `weather_condition.dart`
  /// (`kRainMmHHeavy = 2.5`, `kRainMmHSevere = 7.6`) và ở `AppConfig`
  /// (`rainThresholdMmH = 0.1`, `rainNowThresholdMmH = 0.5`), để mã điều kiện rơi
  /// đúng vào mức mà con người gọi tên: 500 → "mưa nhỏ", 501 → "mưa vừa",
  /// 502 → "mưa to".
  ///
  /// Đây là số ĐẠI DIỆN, không phải số đo. Nó chỉ dùng cho việc phân loại/so
  /// ngưỡng trong `AnalyzeRain`; lượng mưa THẬT vẫn lấy từ `current.rain1h` và
  /// từ hourly (`/timeline/1h` có `rain` đầy đủ).
  @visibleForTesting
  static double precipFromCondition(dynamic weather) {
    if (weather is! List || weather.isEmpty) return 0.0;
    final first = weather.first;
    if (first is! Map) return 0.0;
    final id = first['id'];
    if (id is! num) return 0.0;
    final code = id.toInt();

    // Dông (2xx): luôn coi là mưa to — bỏ sót dông nguy hiểm hơn báo dư.
    if (code >= 200 && code < 300) return 8.0;
    // Mưa phùn (3xx): mưa thật, rất nhẹ. Đặt 0.6 — NGAY TRÊN
    // `rainNowThresholdMmH` (0.5) — có chủ ý: bảng này cố ý KHÔNG có mức nào rơi
    // vào 0.1–0.49, vùng mà `AnalyzeRain` coi là "chưa đủ gọi đang mưa nhưng đủ
    // để hẹn sắp mưa ở mốc sau" ⇒ pha kẹt `rainStartingSoon` và app im lặng mãi.
    // Người đi xe máy dính mưa phùn 30' liên tục thì đó LÀ mưa; yêu cầu duy trì
    // 2 mốc của `_nowcastSaysRainingNow` đã đủ chặn nhiễu một mốc đơn lẻ.
    if (code >= 300 && code < 400) return 0.6;
    // Nhóm mưa 5xx.
    if (code >= 500 && code < 600) {
      return switch (code) {
        500 => 1.0, // mưa nhỏ
        501 => 3.0, // mưa vừa
        502 => 8.0, // mưa to
        503 => 15.0, // mưa rất to
        504 => 25.0, // mưa dữ dội
        511 => 2.0, // mưa băng
        520 => 1.5, // mưa rào nhẹ
        521 => 3.0, // mưa rào
        522 => 8.0, // mưa rào to
        531 => 3.0, // mưa rào rải rác
        _ => 1.0,
      };
    }
    // Tuyết (6xx) và phần còn lại (sương mù 7xx, quang/mây 800+): không phải mưa.
    return 0.0;
  }
}
