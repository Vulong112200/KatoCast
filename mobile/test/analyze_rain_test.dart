import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/hourly.dart';
import 'package:katocast/features/weather/domain/entities/minutely.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather.dart';
import 'package:katocast/features/weather/domain/usecases/analyze_rain.dart';

/// Mốc "bây giờ" cố định cho mọi test (usecase nhận `now` nên test được).
final base = DateTime(2026, 6, 25, 12);

WeatherData _data({
  List<double> minutely = const [],
  List<HourlyForecast> hourly = const [],
  int stepMinutes = 1, // khoảng cách giữa các mốc (1' cho 3.0, 15' cho 4.0)
  DateTime? minutelyStart, // mốc đầu chuỗi minutely (mặc định = base)
}) {
  final start = minutelyStart ?? base;
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
          time: start.add(Duration(minutes: i * stepMinutes)),
          precipitationMmH: minutely[i],
        ),
    ],
    hourly: hourly,
    fetchedAt: base,
  );
}

HourlyForecast _h(int hour, double pop, double rain, {int minute = 0}) =>
    HourlyForecast(
      time: DateTime(2026, 6, 25, hour, minute),
      tempC: 30,
      humidity: 70,
      pop: pop,
      rainMm: rain,
      description: '',
      icon: '',
    );

void main() {
  const sut = AnalyzeRain();

  group('AnalyzeRain - minutely', () {
    test('khô → mưa ở phút 20 ⇒ rainStartingSoon(20) + changeAt đúng mốc', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 20);
      expect(status.changeAt, base.add(const Duration(minutes: 20)));
      expect(status.fromMinutely, true);
    });

    test('đang mưa → tạnh bền vững ở phút 12 ⇒ rainStoppingSoon(12)', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 0; i < 12; i++) {
        minutely[i] = 2.0;
      }
      // từ phút 12 trở đi khô.
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStoppingSoon);
      expect(status.minutesUntilChange, 12);
      expect(status.changeAt, base.add(const Duration(minutes: 12)));
    });

    test('nhiễu 1 phút khô giữa cơn mưa ⇒ KHÔNG báo tạnh sớm', () {
      final minutely = List<double>.filled(60, 2.0);
      minutely[10] = 0.0; // 1 phút lặng giữa mưa
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.raining);
    });

    test('mưa suốt 60 phút ⇒ raining', () {
      final status =
          sut.call(_data(minutely: List<double>.filled(60, 3.0)), now: base);
      expect(status.phase, RainPhase.raining);
    });

    test('khô suốt ⇒ dry', () {
      final status =
          sut.call(_data(minutely: List<double>.filled(60, 0.0)), now: base);
      expect(status.phase, RainPhase.dry);
    });
  });

  group('AnalyzeRain - nowcast 15 phút (One Call 4.0)', () {
    test('khô → mưa ở mốc 15\' thứ 2 ⇒ rainStartingSoon(30) (tính theo time)', () {
      // Dữ liệu cách nhau 15': mưa bắt đầu ở mốc thứ 2 → 30 phút tới.
      final status = sut.call(
        _data(minutely: [0, 0, 2.0, 2.0, 2.0], stepMinutes: 15),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 30); // 2 mốc × 15'
    });
  });

  group('AnalyzeRain - dữ liệu cũ (cache) neo vào now thật', () {
    test('minutely bắt đầu 30\' trước now ⇒ số phút tính từ NOW, không từ mốc đầu',
        () {
      // Chuỗi 1' bắt đầu lúc 11:30 (30' trước now=12:00), mưa từ mốc 40 (12:10).
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 40; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(
        _data(
          minutely: minutely,
          minutelyStart: base.subtract(const Duration(minutes: 30)),
        ),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 10); // 12:10 − 12:00, KHÔNG phải 40.
      expect(status.changeAt, base.add(const Duration(minutes: 10)));
    });

    test('minutely quá cũ (kết thúc trước now) ⇒ bỏ qua, fallback hourly', () {
      // Chuỗi 15' kết thúc lúc 11:00 — không nói gì về 12:00.
      final status = sut.call(
        _data(
          minutely: [2.0, 2.0, 2.0], // "đang mưa" nhưng là chuyện 1 tiếng trước
          stepMinutes: 15,
          minutelyStart: base.subtract(const Duration(minutes: 90)),
          hourly: [_h(12, 0.1, 0), _h(13, 0.9, 2.0)],
        ),
        now: base,
      );
      expect(status.fromMinutely, false);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, DateTime(2026, 6, 25, 13));
    });
  });

  group('AnalyzeRain - fallback hourly', () {
    test('không có minutely, mưa ở giờ thứ 2 ⇒ rainStartingSoon(120)', () {
      final status = sut.call(
        _data(hourly: [_h(12, 0.1, 0), _h(13, 0.2, 0), _h(14, 0.8, 2.0)]),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 120);
      expect(status.changeAt, DateTime(2026, 6, 25, 14));
      expect(status.fromMinutely, false);
    });

    test('giờ hiện tại đã trôi một phần ⇒ số phút thực, không phải bội số 60',
        () {
      // now = 14:50, mưa từ khối giờ 15:00 → còn 10 phút (trước đây báo 60).
      final now = DateTime(2026, 6, 25, 14, 50);
      final status = sut.call(
        _data(hourly: [_h(14, 0.1, 0), _h(15, 0.9, 2.0)]),
        now: now,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 10);
      expect(status.changeAt, DateTime(2026, 6, 25, 15));
    });

    test('onset quá xa (> tầm nhìn 120\') ⇒ coi như dry', () {
      // Mưa ở giờ thứ 3 (180') > rainSoonHorizonMinutes ⇒ chưa báo sắp mưa.
      final status = sut.call(
        _data(hourly: [
          _h(12, 0.1, 0),
          _h(13, 0.1, 0),
          _h(14, 0.2, 0),
          _h(15, 0.9, 3.0),
        ]),
        now: base,
      );
      expect(status.phase, RainPhase.dry);
    });
  });

  group('AnalyzeRain - xác suất mưa (probabilityPct)', () {
    test('hourly fallback: pop lấy tại GIỜ ONSET (theo timestamp), không floor',
        () {
      // Onset 14:00 → pop của giờ 14 (0.9 → 90%), không phải giờ hiện tại (0.1).
      final now = DateTime(2026, 6, 25, 12, 30);
      final status = sut.call(
        _data(hourly: [_h(12, 0.1, 0), _h(13, 0.2, 0), _h(14, 0.9, 2.0)]),
        now: now,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.minutesUntilChange, 90);
      expect(status.probabilityPct, 90);
    });

    test('minutely xác nhận sắp mưa ⇒ floor 80% dù hourly.pop thấp hơn', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(
        _data(minutely: minutely, hourly: [_h(12, 0.7, 0), _h(13, 0.9, 2.0)]),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.probabilityPct, 80); // max(70, floor 80)
    });

    test('minutely xác nhận + hourly.pop cao hơn floor ⇒ giữ pop', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(
        _data(minutely: minutely, hourly: [_h(12, 0.95, 0)]),
        now: base,
      );
      expect(status.probabilityPct, 95);
    });

    test('đang mưa (minutely) nhưng không có hourly ⇒ vẫn có floor 80%', () {
      final status = sut.call(
        _data(minutely: List<double>.filled(60, 3.0)),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
      expect(status.probabilityPct, 80);
    });

    test('dry ⇒ probabilityPct null (không có ý nghĩa hiển thị)', () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          hourly: [_h(12, 0.3, 0)],
        ),
        now: base,
      );
      expect(status.phase, RainPhase.dry);
      expect(status.probabilityPct, isNull);
    });
  });
}
