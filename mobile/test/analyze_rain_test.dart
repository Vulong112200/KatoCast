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

  // Nhóm này khoá lại lỗi thật quan sát trong nhật ký người dùng: app tuyên bố
  // "Trời đang mưa · Mưa nhỏ · 100%" trong khi ngoài trời chỉ ÂM U, rồi pha kẹt
  // ở `raining` hàng chục giờ nên cảnh báo "sắp mưa" không bao giờ xuất hiện và
  // app im lặng luôn.
  group('AnalyzeRain - KHÔNG tuyên bố "đang mưa" từ mưa VẾT', () {
    test('mưa vết 0.15 mm/h bây giờ + mưa thật sau 45\' ⇒ SẮP MƯA, không phải đang mưa',
        () {
      final minutely = List<double>.filled(60, 0.0);
      minutely[0] = 0.15; // vết — trời âm u, OWM vẫn trả số dương
      for (var i = 45; i < 55; i++) {
        minutely[i] = 2.0; // mưa thật
      }
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, RainPhase.rainStartingSoon,
          reason: 'mưa vết không được coi là đang mưa');
      expect(status.changeAt, base.add(const Duration(minutes: 45)));
    });

    test('chỉ có mưa vết suốt cửa sổ ⇒ KHÔNG phải raining', () {
      final minutely = List<double>.filled(60, 0.2);
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.phase, isNot(RainPhase.raining));
    });

    test('một mốc 0.6 mm/h đơn lẻ (không duy trì) ⇒ chưa tuyên bố đang mưa', () {
      final minutely = List<double>.filled(60, 0.0);
      minutely[0] = 0.6;
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.isRainingNow, isFalse);
    });

    test('2 mốc liên tiếp ≥0.5 mm/h ⇒ ĐANG mưa', () {
      final minutely = List<double>.filled(60, 0.0);
      minutely[0] = 0.6;
      minutely[1] = 0.7;
      final status = sut.call(_data(minutely: minutely), now: base);
      // Mưa tắt ngay sau đó nên pha là rainStoppingSoon — vẫn là "đang mưa".
      expect(status.isRainingNow, isTrue);
    });

    test('mưa duy trì cả cửa sổ ⇒ pha raining', () {
      final status = sut.call(
        _data(minutely: List<double>.filled(60, 0.8)),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('mưa rõ ràng ≥2 mm/h ở mốc đầu ⇒ ĐANG mưa ngay, không cần chờ mốc 2', () {
      final minutely = List<double>.filled(60, 0.0);
      minutely[0] = 3.0;
      final status = sut.call(_data(minutely: minutely), now: base);
      expect(status.isRainingNow, isTrue);
    });
  });

  group('AnalyzeRain - quan trắc: mã điều kiện YẾU cần bằng chứng lượng mưa', () {
    test('conditionId 500 (light rain) mà rain1h = 0 ⇒ KHÔNG tuyên bố đang mưa',
        () {
      // Đây chính là ca người dùng gặp: OWM gán 500 cho trời âm u/ẩm cao.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 500,
          rain1h: 0,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
    });

    test(
        'conditionId 500 + rain1h nhỏ NHƯNG nowcast phủ định sạch cửa sổ ⇒ '
        'mưa đã TẠNH, không phải đang mưa', () {
      // ⚠️ Test này TRƯỚC ĐÂY khẳng định điều ngược lại ("500 kèm rain1h > 0 ⇒
      // tin là đang mưa"). Nhật ký thật 01/08/2026 chứng minh giả định đó sai:
      // 12:32–12:55 `nowcast bây giờ 0.00 mm/h · mưa 1h quan trắc 0.74 mm · mã
      // OWM 500` mà app báo "Trời đang mưa · còn mưa 80%" trong khi ngoài trời
      // đã tạnh. `rain1h` là số TÍCH LŨY một giờ nên nó còn dư sau khi mưa tạnh.
      // Hậu quả nặng nhất không phải câu sai mà là pha KẸT ở `raining`: không
      // còn cảnh báo "sắp mưa" nào phát ra nữa.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 500,
          rain1h: 0.3,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
    });

    test('ca thật trong nhật ký: 500 + rain1h 0.74 + nowcast 0.00 ⇒ KHÔNG raining',
        () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 500,
          rain1h: 0.74,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
      // Và vì không phải "đang mưa" nên KHÔNG bị ép sàn xác suất 80% —
      // đây chính là con số vô lý người dùng thấy trên thông báo.
      expect(status.probabilityPct, isNot(80));
    });

    test('conditionId 500 + rain1h LỚN (≥2mm) ⇒ vẫn tin là đang mưa dù nowcast khô',
        () {
      // Van chặn phải HẸP: mưa nhỏ liên tục cả giờ thì nowcast bỏ sót, không
      // phải "dư của cơn đã tạnh" — nowcast ở VN bỏ sót mưa là chuyện thường.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 500,
          rain1h: 2.5,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('conditionId 500 + rain1h nhỏ nhưng nowcast thấy mưa SẮP tới ⇒ raining',
        () {
      // Nowcast chỉ TRỄ chứ không phủ định → quan trắc vẫn thắng.
      final minutely = List<double>.filled(60, 0.0);
      for (var i = 10; i < 30; i++) {
        minutely[i] = 1.0;
      }
      final status = sut.call(
        _data(minutely: minutely, conditionId: 500, rain1h: 0.3),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('không có nowcast: 500 + rain1h nhỏ ⇒ vẫn tin quan trắc (không có gì phủ định)',
        () {
      final status = sut.call(
        _data(hourly: [_h(12, 0.2, 0)], conditionId: 500, rain1h: 0.6),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('drizzle 3xx mà rain1h = 0 ⇒ KHÔNG tuyên bố đang mưa', () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 301,
          rain1h: 0,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
    });

    test(
        'ca thật 06/08: 501 + rain1h 1.55 + nowcast 0.00 sạch cửa sổ ⇒ '
        'KHÔNG raining (mưa vừa TẠNH)', () {
      // ⚠️ Test này thay cho một test cũ khẳng định điều ngược lại ("mã MẠNH 501
      // vẫn tin ngay dù rain1h = 0"). Nhật ký thật 06/08/2026 chứng minh 501 lag
      // đúng như 500: 12:38 → 13:54 liên tục `nowcast bây giờ 0.00 mm/h · mưa 1h
      // quan trắc 1.55→1.14 mm · mã OWM 501`, app báo "Trời đang mưa · còn mưa
      // 100%" rồi KẸT pha `raining` suốt 1h16 (cả 3 lớp nền chỉ ghi "KHÔNG báo —
      // pha trước raining, pha nay raining") nên không còn cảnh báo nào phát ra.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 501,
          rain1h: 1.55,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
      expect(status.probabilityPct, isNot(100));
    });

    test('501 + rain1h LỚN (≥2mm) ⇒ vẫn tin là đang mưa dù nowcast khô', () {
      // Mưa vừa THẬT (2.5–7.6 mm/h) thì rain1h vượt 2 mm rất nhanh → van vẫn cho
      // qua bằng ngưỡng lượng mưa, không cần tin mã điều kiện.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 501,
          rain1h: 2.4,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('501 + rain1h nhỏ nhưng KHÔNG có nowcast phủ định ⇒ tin quan trắc', () {
      final status = sut.call(
        _data(hourly: [_h(12, 0.2, 0)], conditionId: 501, rain1h: 0.2),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('mưa TO 502 vẫn tin ngay dù nowcast phủ định sạch cửa sổ', () {
      // Van cố ý HẸP: mã mưa to trở lên không thể là "dư của cơn mưa nhỏ vừa
      // tạnh", và bỏ sót mưa to thì thiệt hại lớn hơn hẳn một lần báo sai.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 502,
          rain1h: 0,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });

    test('dông 2xx vẫn tin ngay dù rain1h = 0', () {
      final status = sut.call(
        _data(
          minutely: List<double>.filled(60, 0.0),
          conditionId: 202,
          rain1h: 0,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining);
    });
  });

  group('AnalyzeRain - hourly fallback không được coi pop suông là ĐANG mưa', () {
    test('giờ hiện tại pop 80% nhưng không có mm ⇒ không phải raining', () {
      // Trước fix, `_isWetHour` (pop >= 0.5) làm giờ hiện tại thành "đang mưa".
      final status = sut.call(
        _data(hourly: [_h(12, 0.8, 0), _h(13, 0.8, 0)]),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
    });
  });

  group('AnalyzeRain - ca thật 10/08/2026 (mưa nhẹ khi đang đi đường)', () {
    // Nhật ký thật 10/08/2026 18:03:12, người dùng đang đi xe máy về nhà, vị trí
    // ghi nhận `317 Đường số 8, Thông Tây Hội` (đúng trên lộ trình):
    //   pha=dry · tình hình=Mưa nhỏ · mã OWM=500 · mưa 1h quan trắc=0.10 mm
    //   nowcast bây giờ=0.00 mm/h  →  KHÔNG báo
    // Suốt 2 ngày: 168/168 chu kỳ có nowcast = 0.00 và pha = dry, trong khi 37
    // chu kỳ có mã 500 kèm lượng mưa đo được. Nguyên nhân: nowcast 15' của One
    // Call 4.0 không có trường `rain`, bản cũ đọc nhầm nên chuỗi luôn bằng 0.

    test('nowcast SUY TỪ mã 500 (1.0 mm/h) duy trì ⇒ ĐANG mưa', () {
      // Sau khi sửa parse, mốc nowcast mang mã 500 ra 1.0 mm/h.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(8, 1.0),
          stepMinutes: 15,
          conditionId: 500,
          rain1h: 0.10,
        ),
        now: base,
      );
      expect(status.phase, RainPhase.raining,
          reason: 'mưa nhỏ liên tục phải là ĐANG mưa, không phải sắp mưa');
    });

    test('nowcast toàn 0 + rain1h nhỏ ⇒ VẪN không raining (dư của cơn đã tạnh)',
        () {
      // ⚠️ Chủ ý GIỮ van `nowcastSawNoRainAtAll` ở ca này, dù chính nó đã nuốt
      // thông báo hôm 10/08. Lý do: một nowcast CHẠY ĐÚNG và tự tin "hai tiếng
      // tới không mưa" cũng cho toàn số 0 — không thể phân biệt "nowcast chết"
      // với "nowcast chắc chắn khô" bằng giá trị. Nới van ở đây sẽ làm sống lại
      // bug kẹt pha vòng 3/4: `rain1h` là số TÍCH LŨY nên còn dư gần một tiếng
      // sau khi mưa đã tạnh (nhật ký 01/08 `rain1h 0.74 · mã 500`, 06/08
      // `rain1h 1.55 · mã 501` → app báo "đang mưa" lúc trời đã tạnh rồi KẸT pha
      // `raining` hàng giờ = im lặng hoàn toàn).
      //
      // Cách chống nowcast chết KHÔNG phải là ghi đè, mà là PHÁT HIỆN: xem dòng
      // cảnh báo "NGHI VẤN nowcast" trong `weather_check.dart`. Lỗi 168/168 chu
      // kỳ sống sót nhiều tuần chính vì trước đó KHÔNG có dòng log nào.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(8, 0.0),
          stepMinutes: 15,
          conditionId: 500,
          rain1h: 0.10,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.raining));
    });

    test('mốc hiện tại có mưa ⇒ KHÔNG bị gán thành "sắp mưa" ở mốc sau', () {
      // Vùng chết: nếu mốc hiện tại ướt mà pha ra `rainStartingSoon`, mỗi chu kỳ
      // mốc onset lại trượt về sau ⇒ pha đứng yên ⇒ `phaseChanged` không bao giờ
      // true ⇒ app im lặng vĩnh viễn dù ngoài trời đang mưa.
      final status = sut.call(
        _data(
          minutely: List<double>.filled(8, 0.6), // mưa phùn 3xx
          stepMinutes: 15,
          conditionId: 300,
          rain1h: 0.10,
        ),
        now: base,
      );
      expect(status.phase, isNot(RainPhase.rainStartingSoon));
      expect(status.isRainingNow, isTrue);
    });
  });

  group('AnalyzeRain - ca thật 11/08/2026 (ảnh chụp màn hình người dùng)', () {
    // Hai lỗi CÙNG một thông báo, chụp lúc 13:12 và 14:44:
    //   "Sắp mưa … Dự kiến mưa lúc 18:30 (khoảng 317 phút tới) … Khả năng mưa
    //    khoảng 0%."
    // (1) 317' (và 225' ở ảnh sau) vượt xa `rainSoonHorizonMinutes` = 120'.
    // (2) báo mưa mà xác suất 0% — câu tự phủ định chính nó.
    // Cả hai lộ ra SAU khi sửa lỗi parse nowcast: trước đó chuỗi nowcast bị ghim
    // cứng 0.0 nên nhánh onset-từ-nowcast KHÔNG BAO GIỜ chạy.

    test('onset nowcast XA hơn tầm nhìn 120 phút ⇒ KHÔNG báo "sắp mưa"', () {
      // 21 mốc × 15' = mưa bắt đầu ở phút 315 (~5h15) — đúng ca 13:12 → 18:30.
      final minutely = List<double>.filled(40, 0.0);
      for (var i = 21; i < 30; i++) {
        minutely[i] = 1.0; // mã 500 → 1.0 mm/h
      }
      final status = sut.call(
        _data(minutely: minutely, stepMinutes: 15),
        now: base,
      );
      expect(status.phase, RainPhase.dry,
          reason: 'mưa còn cách 5 tiếng thì chưa phải "sắp mưa"');
    });

    test('onset nowcast TRONG tầm nhìn ⇒ vẫn báo bình thường', () {
      // Không được siết tay: mốc thứ 4 (60') phải còn báo.
      final minutely = List<double>.filled(40, 0.0);
      for (var i = 4; i < 12; i++) {
        minutely[i] = 1.0;
      }
      final status = sut.call(
        _data(minutely: minutely, stepMinutes: 15),
        now: base,
      );
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.changeAt, base.add(const Duration(minutes: 60)));
    });

    test('xác suất lấy MAX với pop nowcast ⇒ không còn ra 0%', () {
      // Ca thật: hourly cho giờ đó báo pop = 0 trong khi nowcast trong chính giờ
      // đó lên tới 0.17 — cảnh báo do nowcast sinh ra mà % lại lấy từ hourly.
      final minutely = <MinutelyForecast>[
        for (var i = 0; i < 12; i++)
          MinutelyForecast(
            time: base.add(Duration(minutes: 15 * i)),
            precipitationMmH: i >= 4 ? 1.0 : 0.0,
            pop: i >= 4 ? 0.17 : 0.0,
          ),
      ];
      final data = WeatherData(
        current: CurrentWeather(
          time: base,
          tempC: 32,
          feelsLikeC: 39,
          humidity: 66,
          uvi: 4,
          clouds: 100,
          windSpeed: 7.3,
          conditionId: 804,
          description: 'u ám',
          icon: '04d',
          rain1h: 0,
        ),
        minutely: minutely,
        hourly: [_h(12, 0.0, 0), _h(13, 0.0, 0)],
        fetchedAt: base,
      );
      final status = sut.call(data, now: base);
      expect(status.phase, RainPhase.rainStartingSoon);
      expect(status.probabilityPct, 17,
          reason: 'phải dùng pop của chính mốc nowcast đã sinh ra cảnh báo');
    });
  });
}
