import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/hourly.dart';
import 'package:katocast/features/weather/domain/entities/weather.dart';
import 'package:katocast/features/weather/domain/usecases/build_rain_outlook.dart';

/// Dựng 1 giờ dự báo tối giản (chỉ cần time + pop + rainMm cho outlook).
HourlyForecast _h(DateTime time, double pop, {double rainMm = 0}) => HourlyForecast(
      time: time,
      tempC: 30,
      humidity: 70,
      pop: pop,
      rainMm: rainMm,
      description: '',
      icon: '',
    );

WeatherData _data(List<HourlyForecast> hourly, DateTime fetchedAt) => WeatherData(
      current: CurrentWeather(
        time: fetchedAt,
        tempC: 30,
        feelsLikeC: 34,
        humidity: 70,
        uvi: 5,
        clouds: 80,
        windSpeed: 2,
        conditionId: 803,
        description: 'mây',
        icon: '04d',
        rain1h: 0,
      ),
      minutely: const [],
      hourly: hourly,
      fetchedAt: fetchedAt,
    );

void main() {
  group('BuildRainOutlook', () {
    test('mưa buổi chiều → nêu khung giờ + % và các buổi khô', () {
      final now = DateTime(2026, 7, 1, 6, 0);
      final hourly = [
        for (var hour = 6; hour <= 22; hour++)
          _h(DateTime(2026, 7, 1, hour), (hour == 14 || hour == 15) ? 0.7 : 0.1),
      ];

      final result = const BuildRainOutlook().call(_data(hourly, now), now: now);

      expect(result, isNotNull);
      expect(result, contains('Chiều có mưa (~14:00–16:00, khả năng ~70%)'));
      expect(result, contains('khô ráo'));
    });

    test('không có giờ nào đạt ngưỡng → ít khả năng mưa', () {
      final now = DateTime(2026, 7, 1, 6, 0);
      final hourly = [
        for (var hour = 6; hour <= 22; hour++) _h(DateTime(2026, 7, 1, hour), 0.1),
      ];

      final result = const BuildRainOutlook().call(_data(hourly, now), now: now);

      expect(result, 'Hôm nay ít khả năng mưa.');
    });

    test('không còn giờ nào của hôm nay → null', () {
      final now = DateTime(2026, 7, 1, 23, 30);
      final hourly = [
        // Chỉ có dữ liệu của ngày mai.
        for (var hour = 0; hour <= 5; hour++) _h(DateTime(2026, 7, 2, hour), 0.8),
      ];

      final result = const BuildRainOutlook().call(_data(hourly, now), now: now);

      expect(result, isNull);
    });
  });
}
