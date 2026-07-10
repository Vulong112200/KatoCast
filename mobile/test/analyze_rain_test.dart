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
  int conditionId = 803, // mã điều kiện quan trắc hiện tại
  double rain1h = 0, // lượng mưa quan trắc 1h gần nhất
  DateTime? currentTime, // thời điểm quan trắc (mặc định = base)
}) {
  final start = minutelyStart ?? base;
  return WeatherData(
    current: CurrentWeather(
      time: currentTime ?? base,
      tempC: 30,
      feelsLikeC: 32,
      humidity: 70,
      uvi: 5,
      clouds: 40,
      windSpeed: 2,
      conditionId: conditionId,
      description: 'mây',
      icon: '03d',
      rain1h: rain1h,
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

    test('SẮP mưa (nowcast) KHÔNG floor ⇒ hiện pop THẬT dù thấp', () {
      // Onset 20\' → nằm trong giờ 12 (pop 0.3). Trước đây bị ép sàn 80%; nay
      // "sắp mưa" hiện đúng 30% (chỉ ép sàn khi ĐANG mưa).
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(
        _data(minutely: minutely, hourly: [_h(12, 0.3, 0), _h(13, 0.9, 2.0)]),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.probabilityPct, 30); // pop thật, không còn ép sàn
    });

    test('SẮP mưa + hourly.pop cao ⇒ giữ pop thật', () {
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

  group('AnalyzeRain - rainEndsAt / durationMinutes (mưa kéo dài đến bao giờ)', () {
    test('sắp mưa rồi tạnh bền vững ⇒ rainEndsAt + duration đúng', () {
      // Khô, mưa từ phút 20 đến 29, khô bền vững từ phút 30.
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 30; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, base.add(const Duration(minutes: 20)));
      expect(status.rainEndsAt, base.add(const Duration(minutes: 30)));
      expect(status.durationMinutes, 10);
    });

    test('mưa kéo dài tới hết cửa sổ ⇒ rainEndsAt null', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.rainEndsAt, isNull);
      expect(status.durationMinutes, isNull);
    });

    test('hourly fallback: sắp mưa giờ 14, tạnh giờ 15 ⇒ rainEndsAt = 15:00', () {
      final status = sut.call(
        _data(hourly: [_h(12, 0.1, 0), _h(13, 0.2, 0), _h(14, 0.9, 2.0), _h(15, 0.1, 0)]),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, DateTime(2026, 6, 25, 14));
      expect(status.rainEndsAt, DateTime(2026, 6, 25, 15));
    });

    test('minutely onset kéo dài quá cửa sổ ⇒ nối tiếp hourly để có giờ tạnh',
        () {
      // Nowcast: mưa từ phút 20 đến hết cửa sổ (không thấy tạnh). Hourly nói
      // giờ 12 & 13 ướt, giờ 14 khô → giờ tạnh 14:00 lấy từ hourly.
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 20; i < 60; i++) {
        minutely[i] = 1.5;
      }
      final status = sut.call(
        _data(
          minutely: minutely,
          hourly: [_h(12, 0.7, 2.0), _h(13, 0.9, 3.0), _h(14, 0.1, 0)],
        ),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, base.add(const Duration(minutes: 20)));
      expect(status.rainEndsAt, DateTime(2026, 6, 25, 14));
      // 2 đoạn cường độ: mưa nhỏ (2.0) rồi mưa vừa (3.0).
      expect(status.segments.length, 2);
      expect(status.segments.first.start, base.add(const Duration(minutes: 20)));
      expect(status.segments.first.intensity, RainIntensity.light);
      expect(status.segments.last.intensity, RainIntensity.moderate);
      expect(status.segments.last.end, DateTime(2026, 6, 25, 14));
    });
  });

  group('AnalyzeRain - nowcast khô vẫn đối chiếu hourly (chống bỏ sót)', () {
    test('minutely khô suốt + hourly ướt NGOÀI cửa sổ ⇒ rainStartingSoon', () {
      // Nowcast 8 slot 15' (12:00–13:45, cửa sổ khô tới 14:00). Hourly nói
      // giờ 14 mưa → cảnh báo sớm 120' thay vì im lặng như trước.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(8, 0.0),
          stepMinutes: 15,
          hourly: [_h(12, 0.1, 0), _h(13, 0.2, 0), _h(14, 0.7, 1.0)],
        ),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, DateTime(2026, 6, 25, 14));
      expect(status.fromMinutely, false);
      expect(status.probabilityPct, 70);
    });

    test('hourly tín hiệu MẠNH đè lên cửa sổ nowcast khô ⇒ onset sau cửa sổ',
        () {
      // Nowcast 6 slot (12:00–13:15, cửa sổ khô tới 13:30). Giờ 13 có mm thật
      // + pop cao (mâu thuẫn nowcast) → tin hourly, mưa sớm nhất 13:30.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(6, 0.0),
          stepMinutes: 15,
          hourly: [_h(12, 0.1, 0), _h(13, 0.8, 1.5)],
        ),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, DateTime(2026, 6, 25, 13, 30));
      expect(status.minutesUntilChange, 90);
    });

    test('hourly chỉ có pop suông TRONG cửa sổ nowcast khô ⇒ vẫn dry', () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(6, 0.0),
          stepMinutes: 15,
          hourly: [_h(12, 0.6, 0), _h(13, 0.8, 0)],
        ),
        now: base,
      );
      expect(status.phase, RainPhase.dry);
    });
  });

  group('AnalyzeRain - quan trắc hiện tại (đang mưa thật)', () {
    test('nowcast bảo khô nhưng conditionId là mưa ⇒ raining (tin quan trắc)',
        () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 501,
          rain1h: 2.0,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
      expect(status.probabilityPct, 80); // floor vì nguồn ngắn hạn xác nhận
    });

    test('quan trắc mưa nhưng QUÁ CŨ (>30\') ⇒ không đè, vẫn dry', () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 501,
          rain1h: 2.0,
          currentTime: base.subtract(const Duration(minutes: 45)),
        ),
        now: base,
      );
      expect(status.phase, RainPhase.dry);
    });

    test('quan trắc mưa đè lên "sắp mưa" của nowcast trễ ⇒ raining ngay', () {
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 10; i < 30; i++) {
        minutely[i] = 1.0; // nowcast nghĩ 10' nữa mới mưa
      }
      final status = sut.call(
        _data(minutely: minutely, conditionId: 500, rain1h: 1.0),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });
  });

  group('AnalyzeRain - segments (diễn biến theo đoạn cường độ)', () {
    test('chuỗi giờ đổi cường độ ⇒ tách đoạn: mưa vừa rồi mưa nhỏ', () {
      final status = sut.call(
        _data(hourly: [
          _h(12, 0.2, 0),
          _h(13, 0.9, 3.0), // vừa
          _h(14, 0.9, 4.0), // vừa (gộp)
          _h(15, 0.8, 1.0), // nhỏ
          _h(16, 0.1, 0), // khô → tạnh 16:00
        ]),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.rainEndsAt, DateTime(2026, 6, 25, 16));
      expect(status.segments.length, 2);
      expect(status.segments[0].intensity, RainIntensity.moderate);
      expect(status.segments[0].start, DateTime(2026, 6, 25, 13));
      expect(status.segments[0].end, DateTime(2026, 6, 25, 15));
      expect(status.segments[1].intensity, RainIntensity.light);
      expect(status.segments[1].end, DateTime(2026, 6, 25, 16));
      expect(
        describeRainCourse(status.segments),
        'mưa vừa ~13:00–15:00, sau đó mưa nhỏ ~15:00–16:00',
      );
    });

    test('giờ chỉ có pop cao (không mm) ⇒ đoạn "possible", ướt tới hết dữ liệu'
        ' ⇒ end null', () {
      final status = sut.call(
        _data(hourly: [_h(12, 0.2, 0), _h(13, 0.6, 1.0), _h(14, 0.7, 0)]),
        now: base,
      );
      expect(status.segments.length, 2);
      expect(status.segments[1].intensity, RainIntensity.possible);
      expect(status.segments[1].end, isNull); // hết dữ liệu khi còn ướt
      expect(status.rainEndsAt, isNull);
    });

    test('2 cơn mưa trong nowcast: cường độ đoạn ĐẦU không bị cơn sau thổi phồng',
        () {
      // Cơn A: phút 5–14 mưa nhỏ (1.5). Khô bền vững từ phút 15. Cơn B: phút
      // 30–40 mưa TO (10.0). Đoạn mưa sắp tới (cơn A, gói trong cửa sổ) phải là
      // "mưa nhỏ" — trước fix, _maxMinutelyRate quét tới hết nên nhận nhầm cơn B.
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 5; i < 15; i++) {
        minutely[i] = 1.5;
      }
      for (var i = 30; i < 41; i++) {
        minutely[i] = 10.0;
      }
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, base.add(const Duration(minutes: 5)));
      expect(status.rainEndsAt, base.add(const Duration(minutes: 15)));
      expect(status.segments.length, 1);
      expect(status.segments.first.intensity, RainIntensity.light);
    });
  });
}
