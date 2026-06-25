import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/hourly.dart';
import 'package:katocast/features/weather/domain/entities/minutely.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather.dart';
import 'package:katocast/features/weather/domain/usecases/analyze_rain.dart';

WeatherData _data({
  List<double> minutely = const [],
  List<HourlyForecast> hourly = const [],
  int stepMinutes = 1, // khoảng cách giữa các mốc (1' cho 3.0, 15' cho 4.0)
}) {
  final base = DateTime(2026, 6, 25, 12);
  return WeatherData(
    current: CurrentWeather(
      time: base,
      tempC: 30,
      feelsLikeC: 32,
      humidity: 70,
      uvi: 5,
      clouds: 40,
      windSpeed: 2,
      conditionId: 803,
      description: 'mây',
      icon: '03d',
      rain1h: 0,
    ),
    minutely: [
      for (var i = 0; i < minutely.length; i++)
        MinutelyForecast(
          time: base.add(Duration(minutes: i * stepMinutes)),
          precipitationMmH: minutely[i],
        ),
    ],
    hourly: hourly,
    fetchedAt: base,
  );
}

void main() {
  const sut = AnalyzeRain();

  group('AnalyzeRain - minutely', () {
    test('khô → mưa ở phút 20 ⇒ rainStartingSoon(20)', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(_data(minutely: minutely));
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 20);
      expect(status.fromMinutely, true);
    });

    test('đang mưa → tạnh bền vững ở phút 12 ⇒ rainStoppingSoon(12)', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 0; i < 12; i++) {
        minutely[i] = 2.0;
      }
      // từ phút 12 trở đi khô.
      final status = sut.call(_data(minutely: minutely));
      expect(status.phase, RainPhase.rainStoppingSoon);
      expect(status.minutesUntilChange, 12);
    });

    test('nhiễu 1 phút khô giữa cơn mưa ⇒ KHÔNG báo tạnh sớm', () {
      final minutely = List<double>.filled(60, 2.0);
      minutely[10] = 0.0; // 1 phút lặng giữa mưa
      final status = sut.call(_data(minutely: minutely));
      expect(status.phase, RainPhase.raining);
    });

    test('mưa suốt 60 phút ⇒ raining', () {
      final status = sut.call(_data(minutely: List<double>.filled(60, 3.0)));
      expect(status.phase, RainPhase.raining);
    });

    test('khô suốt ⇒ dry', () {
      final status = sut.call(_data(minutely: List<double>.filled(60, 0.0)));
      expect(status.phase, RainPhase.dry);
    });
  });

  group('AnalyzeRain - nowcast 15 phút (One Call 4.0)', () {
    test('khô → mưa ở mốc 15\' thứ 2 ⇒ rainStartingSoon(30) (tính theo time)', () {
      // Dữ liệu cách nhau 15': mưa bắt đầu ở mốc thứ 2 → 30 phút tới.
      final status = sut.call(
        _data(minutely: [0, 0, 2.0, 2.0, 2.0], stepMinutes: 15),
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 30); // 2 mốc × 15'
    });
  });

  group('AnalyzeRain - fallback hourly', () {
    HourlyForecast h(int hour, double pop, double rain) => HourlyForecast(
          time: DateTime(2026, 6, 25, hour),
          tempC: 30,
          humidity: 70,
          pop: pop,
          rainMm: rain,
          description: '',
          icon: '',
        );

    test('không có minutely, mưa ở giờ thứ 2 ⇒ rainStartingSoon(120)', () {
      final status = sut.call(_data(hourly: [
        h(12, 0.1, 0),
        h(13, 0.2, 0),
        h(14, 0.8, 2.0),
      ]));
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 120);
      expect(status.fromMinutely, false);
    });
  });
}
