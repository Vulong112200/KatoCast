import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/alerts/domain/usecases/build_weather_alerts.dart';
import 'package:katocast/features/weather/data/datasources/weather_remote_datasource.dart';
import 'package:katocast/features/weather/data/models/weather_model.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';
import 'package:katocast/features/weather/domain/usecases/analyze_rain.dart';
import 'package:katocast/features/weather/domain/usecases/detect_env_change.dart';

/// Test HỒI QUY đầu-cuối cho vụ 10/08/2026: payload One Call 4.0 THẬT chạy qua
/// đúng đường ống của app (chuẩn hoá → mapper → AnalyzeRain → BuildWeatherAlerts)
/// và phải kết thúc bằng MỘT thông báo.
///
/// Vì sao cần test xuyên tầng: mỗi tầng riêng lẻ đều "đúng" theo test của nó,
/// nhưng chỗ hỏng nằm ở KHỚP NỐI giữa payload 4.0 và `AnalyzeRain` — không test
/// nào chạm tới, nên lỗi sống sót nhiều tuần và chỉ lộ ra khi đọc nhật ký thật.
void main() {
  final now = DateTime(2026, 8, 10, 18, 3);
  int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

  /// Bản ghi nowcast 15' đúng shape THẬT của 4.0: có `pop` + `weather[]`,
  /// **không có** `rain`.
  Map<String, dynamic> slot(DateTime at, int conditionId, double pop) => {
    'dt': ts(at),
    'temp': 27.0,
    'humidity': 88,
    'pop': pop,
    'weather': [
      {'id': conditionId, 'description': 'mưa nhỏ', 'icon': '10n'},
    ],
  };

  Map<String, dynamic> hour(
    DateTime at,
    int conditionId,
    double pop,
    double rainMm,
  ) => {
    'dt': ts(at),
    'temp': 27.0,
    'humidity': 88,
    'pop': pop,
    'rain': {'1h': rainMm},
    'weather': [
      {'id': conditionId, 'description': 'mưa nhỏ', 'icon': '10n'},
    ],
  };

  test('ca thật 10/08 18:03 — mưa nhỏ khi đang đi đường ⇒ PHẢI có thông báo', () {
    // Nhật ký thật, chu kỳ 18:03:12 tại `317 Đường số 8, Thông Tây Hội`:
    //   mã điều kiện OWM = 500 · mưa 1h quan trắc = 0.10 mm
    // Trước fix: nowcast ra 0.00 ⇒ pha dry ⇒ KHÔNG báo (im lặng cả quãng đường).
    final merged = WeatherRemoteDataSource.normalizeOneCall(
      current: {
        'dt': ts(now),
        'temp': 27.0,
        'feels_like': 30.0,
        'humidity': 88,
        'uvi': 0.0,
        'clouds': 100,
        'wind_speed': 2.0,
        'rain': {'1h': 0.10},
        'weather': [
          {'id': 500, 'description': 'mưa nhỏ', 'icon': '10n'},
        ],
      },
      min15: [
        for (var i = 0; i < 8; i++)
          slot(now.add(Duration(minutes: 15 * i)), 500, 0.38),
      ],
      hourly: [
        hour(DateTime(2026, 8, 10, 18), 500, 0.38, 0.3),
        hour(DateTime(2026, 8, 10, 19), 500, 0.38, 0.3),
      ],
    );

    final data = WeatherMapper.fromOneCallJson(merged, fetchedAt: now);

    // 1) Chuỗi nowcast phải mang tín hiệu mưa — đây là dòng đã hỏng.
    expect(
      data.minutely.first.precipitationMmH,
      greaterThan(0),
      reason: 'nowcast 15p phải suy được lượng mưa từ weather[].id',
    );

    // 2) Phân tích phải kết luận ĐANG mưa.
    final rain = const AnalyzeRain().call(data, now: now);
    expect(rain.phase, RainPhase.raining);

    // 3) …và phải sinh ra thông báo (previousPhase = dry như nhật ký thật).
    final out = const BuildWeatherAlerts().call(
      rain: rain,
      condition: WeatherCondition.classify(
        data.current.conditionId,
        rainMmH: data.current.rain1h,
      ),
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.cloudy,
      observedRain1hMm: data.current.rain1h,
      now: now,
    );
    expect(
      out.alerts,
      isNotEmpty,
      reason: 'trời đang mưa mà app vẫn im lặng là lỗi gốc của vụ 10/08',
    );
    expect(out.alerts.map((a) => a.title).join(' | '), contains('mưa'));
    expect(out.suppressedReason, isNull);
  });

  test('trời chỉ nhiều mây ⇒ KHÔNG bịa ra mưa (chống hồi quy chiều ngược)', () {
    // Lưới quan trọng không kém: bảng ánh xạ mã→mm không được biến trời âm u
    // thành mưa, nếu không sẽ sống lại đúng lỗi spam mà vòng 3–4 đã sửa.
    final merged = WeatherRemoteDataSource.normalizeOneCall(
      current: {
        'dt': ts(now),
        'temp': 32.0,
        'humidity': 66,
        'clouds': 100,
        'wind_speed': 2.0,
        'weather': [
          {'id': 804, 'description': 'mây đen u ám', 'icon': '04d'},
        ],
      },
      min15: [
        for (var i = 0; i < 8; i++)
          slot(now.add(Duration(minutes: 15 * i)), 804, 0.04),
      ],
      hourly: [hour(DateTime(2026, 8, 10, 18), 804, 0.04, 0)],
    );

    final data = WeatherMapper.fromOneCallJson(merged, fetchedAt: now);
    expect(data.minutely.every((m) => m.precipitationMmH == 0), isTrue);

    final rain = const AnalyzeRain().call(data, now: now);
    expect(rain.phase, RainPhase.dry);
  });
}
