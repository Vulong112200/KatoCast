import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/data/models/weather_model.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';

/// Kiểm tra mapper JSON → entity: phân biệt "thiếu dữ liệu" (null) với "0 thật",
/// và trích đủ các trường chi tiết của One Call 4.0.
void main() {
  final fetchedAt = DateTime(2026, 6, 25, 12);

  Map<String, dynamic> oneCall(Map<String, dynamic> current) => {
        'current': current,
        'minutely': const [],
        'hourly': const [],
      };

  group('WeatherMapper - dữ liệu thiếu ⇒ null (không mặc định 0)', () {
    test('thiếu temp/humidity/uvi ⇒ các trường null', () {
      final data = WeatherMapper.fromOneCallJson(
        oneCall({
          'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
          'weather': [
            {'id': 500, 'description': 'mưa nhỏ', 'icon': '10d'},
          ],
        }),
        fetchedAt: fetchedAt,
      );
      expect(data.current.tempC, isNull);
      expect(data.current.humidity, isNull);
      expect(data.current.uvi, isNull);
      expect(data.current.rain1h, 0); // vắng mưa = 0 (đúng ngữ nghĩa)
    });

    test('thiếu weather[] ⇒ conditionId null ⇒ classify "Không rõ tình hình"', () {
      final data = WeatherMapper.fromOneCallJson(
        oneCall({
          'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
          'temp': 30.0,
        }),
        fetchedAt: fetchedAt,
      );
      expect(data.current.conditionId, isNull);
      final c = WeatherCondition.classify(data.current.conditionId);
      expect(c.category, WeatherCategory.other);
      expect(c.label, 'Không rõ tình hình');
    });
  });

  test('minutely mang pop (nowcast), hourly mang conditionId', () {
    final data = WeatherMapper.fromOneCallJson(
      {
        'current': {
          'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
          'temp': 30.0,
          'weather': [
            {'id': 803, 'description': 'nhiều mây', 'icon': '04d'},
          ],
        },
        'minutely': [
          {
            'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
            'precipitation': 0.0,
            'pop': 0.42,
          },
        ],
        'hourly': [
          {
            'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
            'temp': 30.0,
            'humidity': 60,
            'pop': 0.1,
            'weather': [
              {'id': 500, 'description': 'mưa nhỏ', 'icon': '10d'},
            ],
          },
        ],
      },
      fetchedAt: fetchedAt,
    );
    expect(data.minutely.single.pop, 0.42);
    expect(data.hourly.single.conditionId, 500);
  });

  group('WeatherMapper - trích đủ trường chi tiết 4.0', () {
    test('dew_point/pressure/visibility/wind_gust/wind_deg', () {
      final data = WeatherMapper.fromOneCallJson(
        oneCall({
          'dt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
          'temp': 30.0,
          'feels_like': 33.0,
          'humidity': 70,
          'uvi': 6.0,
          'clouds': 40,
          'wind_speed': 3.5,
          'wind_deg': 90,
          'wind_gust': 6.2,
          'pressure': 1008,
          'dew_point': 24.5,
          'visibility': 8000,
          'weather': [
            {'id': 803, 'description': 'nhiều mây', 'icon': '04d'},
          ],
        }),
        fetchedAt: fetchedAt,
      );
      final c = data.current;
      expect(c.tempC, 30.0);
      expect(c.windDeg, 90);
      expect(c.windGust, 6.2);
      expect(c.pressure, 1008);
      expect(c.dewPointC, 24.5);
      expect(c.visibilityM, 8000);
      expect(c.conditionId, 803);
    });
  });
}
