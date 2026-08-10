import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/alerts/domain/usecases/build_weather_alerts.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';
import 'package:katocast/features/weather/domain/usecases/detect_env_change.dart';

/// Điều kiện mặc định (trời quang) để cô lập từng nhánh test.
final _clear = WeatherCondition.classify(800);

/// Mốc "bây giờ" cố định.
final _now = DateTime(2026, 7, 1, 14, 0);

void main() {
  const sut = BuildWeatherAlerts();

  test('khô → sắp mưa ⇒ 1 thông báo, giờ HH:MM lấy từ changeAt (không drift)',
      () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 20)),
        minutesUntilChange: 20,
        fromMinutely: true,
        probabilityPct: 85,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts.length, 1);
    expect(r.alerts.first.body, contains('lúc 14:20'));
    expect(r.alerts.first.body, contains('20 phút'));
    expect(r.alerts.first.body, contains('85%'));
    expect(r.newPhase, RainPhase.rainStartingSoon);
    expect(r.newChangeAt, _now.add(const Duration(minutes: 20)));
  });

  test('sắp mưa "0 phút" ⇒ nói "ngay bây giờ" thay vì giờ lệch', () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now,
        minutesUntilChange: 0,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts.single.body, contains('ngay bây giờ'));
  });

  test('cùng pha & thời điểm không lệch đáng kể ⇒ KHÔNG phát (chống spam)', () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 18)),
        minutesUntilChange: 18,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      // Lần trước đã báo mưa lúc 14:25 — lệch 7' < 15' ⇒ im lặng.
      previousChangeAt: _now.add(const Duration(minutes: 25)),
      now: _now,
    );
    expect(r.alerts, isEmpty);
    // Không phát ⇒ GIỮ mốc đã báo lần trước (không ghi đè) để dự báo "trôi"
    // dần vẫn cộng dồn được độ lệch và bắn "Cập nhật" đúng lúc.
    expect(r.newChangeAt, _now.add(const Duration(minutes: 25)));
  });

  test('cùng pha nhưng thời điểm lệch ≥15\' ⇒ phát bản "Cập nhật"', () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 20)), // 14:20
        minutesUntilChange: 20,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      // Lần trước đã báo mưa lúc 15:00 — dự báo mới sớm hơn 40'.
      previousChangeAt: _now.add(const Duration(minutes: 60)),
      now: _now,
    );
    expect(r.alerts.length, 1);
    expect(r.alerts.single.title, startsWith('Cập nhật:'));
    expect(r.alerts.single.body, contains('lúc 14:20'));
    expect(r.newChangeAt, _now.add(const Duration(minutes: 20)));
  });

  test('cùng pha, chưa từng lưu thời điểm (previousChangeAt null) ⇒ không phát',
      () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 20)),
        minutesUntilChange: 20,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts, isEmpty);
  });

  test('đang mưa → tạnh ⇒ phát thông báo đã tạnh', () {
    final r = sut.call(
      rain: const RainStatus.dry(),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.raining,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts.any((a) => a.body.contains('tạnh')), true);
  });

  test('đổi nhóm thời tiết (mây → bão lớn) ⇒ phát thông báo tình hình', () {
    final storm = WeatherCondition.classify(212); // dông mạnh
    final r = sut.call(
      rain: const RainStatus.raining(),
      condition: storm,
      env: EnvChange.none,
      previousPhase: RainPhase.raining,
      previousCategory: WeatherCategory.cloudy,
      now: _now,
    );
    final conditionAlert =
        r.alerts.where((a) => a.title.contains('Bão lớn')).toList();
    expect(conditionAlert, isNotEmpty);
    expect(r.newCategory, WeatherCategory.severeStorm);
  });

  test('cùng nhóm thời tiết ⇒ không phát lại thông báo tình hình', () {
    final r = sut.call(
      rain: const RainStatus.dry(),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts, isEmpty);
  });

  test('mưa DỜI MUỘN 30\' (< ngưỡng muộn 45\') ⇒ im lặng, tránh spam trôi giờ',
      () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 50)),
        minutesUntilChange: 50,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      previousChangeAt: _now.add(const Duration(minutes: 20)),
      now: _now,
    );
    expect(r.alerts, isEmpty);
  });

  test('mưa DỜI MUỘN ≥45\' ⇒ phát bản "Cập nhật"', () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: _now.add(const Duration(minutes: 70)),
        minutesUntilChange: 70,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      previousChangeAt: _now.add(const Duration(minutes: 20)),
      now: _now,
    );
    expect(r.alerts.single.title, startsWith('Cập nhật:'));
  });

  test('đã báo từ XA, cơn mưa áp sát còn ≤35\' ⇒ nhắc lại một lần', () {
    final changeAt = _now.add(const Duration(minutes: 30));
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: changeAt,
        minutesUntilChange: 30,
        fromMinutely: true,
        probabilityPct: 85,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      previousChangeAt: changeAt, // cùng cơn mưa, giờ không đổi
      // Đã báo lúc 12:30 — khi đó còn 120' (từ xa).
      previousNotifiedAt: _now.subtract(const Duration(minutes: 90)),
      now: _now,
    );
    expect(r.alerts.length, 1);
    expect(r.alerts.single.title, contains('còn khoảng 30 phút'));
    expect(r.alerts.single.body, contains('lúc 14:30'));
    // Đã nhắc ⇒ notifiedAt chốt lại tại thời điểm nhắc (không nhắc lặp).
    expect(r.newNotifiedAt, _now);
  });

  test('báo lần đầu khi cơn mưa đã GẦN (≤35\') ⇒ không nhắc lại lần nữa', () {
    final changeAt = _now.add(const Duration(minutes: 20));
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: changeAt,
        minutesUntilChange: 20,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
      previousChangeAt: changeAt,
      // Lần báo trước chỉ cách onset 30' (≤35') ⇒ người dùng đã được báo gần.
      previousNotifiedAt: changeAt.subtract(const Duration(minutes: 30)),
      now: _now,
    );
    expect(r.alerts, isEmpty);
  });

  test('sắp mưa với nhiều đoạn cường độ ⇒ body mô tả diễn biến từng đoạn', () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: DateTime(2026, 7, 1, 17),
        minutesUntilChange: 180,
        rainEndsAt: DateTime(2026, 7, 1, 21),
        segments: [
          RainSegment(
            start: DateTime(2026, 7, 1, 17),
            end: DateTime(2026, 7, 1, 19),
            intensity: RainIntensity.moderate,
          ),
          RainSegment(
            start: DateTime(2026, 7, 1, 19),
            end: DateTime(2026, 7, 1, 21),
            intensity: RainIntensity.light,
          ),
        ],
        fromMinutely: false,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    final body = r.alerts.single.body;
    expect(body, contains('Diễn biến: mưa vừa ~17:00–19:00'));
    expect(body, contains('sau đó mưa nhỏ ~19:00–21:00'));
    // Không còn câu "kéo dài đến 21:00" trần trụi gây hiểu lầm mưa to suốt.
    expect(body, isNot(contains('kéo dài đến')));
  });

  test('đoạn duy nhất chỉ suy từ xác suất (possible) ⇒ câu nói mềm "có thể"',
      () {
    final r = sut.call(
      rain: RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: DateTime(2026, 7, 1, 15),
        minutesUntilChange: 60,
        rainEndsAt: DateTime(2026, 7, 1, 20),
        segments: [
          RainSegment(
            start: DateTime(2026, 7, 1, 15),
            end: DateTime(2026, 7, 1, 20),
            intensity: RainIntensity.possible,
          ),
        ],
        fromMinutely: false,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      now: _now,
    );
    expect(r.alerts.single.body,
        contains('Có thể có mưa rải rác đến khoảng 20:00'));
  });

  test('thay đổi môi trường mạnh lần đầu ⇒ phát; lần sau (đã notified) ⇒ không',
      () {
    const env = EnvChange(hasStrongChange: true, tempDeltaC: 6, humidityDeltaPct: 5);

    final first = sut.call(
      rain: const RainStatus.dry(),
      condition: _clear,
      env: env,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      envAlreadyNotified: false,
      now: _now,
    );
    expect(first.alerts.any((a) => a.body.contains('thú cưng')), true);
    expect(first.envNotified, true);

    final second = sut.call(
      rain: const RainStatus.dry(),
      condition: _clear,
      env: env,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
      envAlreadyNotified: true,
      now: _now,
    );
    expect(second.alerts, isEmpty);
  });

  group('KHỞI ĐẦU MỚI (previousCategory == null) không spam tình hình vô hại', () {
    test('trời nhiều mây ⇒ KHÔNG báo gì', () {
      // Ca thật trong nhật ký: mỗi lần app hồi sinh sau một khoảng đứt dài,
      // `AlertStateStore` hết hạn → previousCategory null → bản cũ luôn phát
      // "🌤️ Nhiều mây — Trời nhiều mây." (02/08 06:50, 04/08 12:33). Đó là
      // phần lớn số thông báo trong ngày mà không nói được điều gì hữu ích.
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(803), // nhiều mây
        env: EnvChange.none,
        now: _now,
      );
      expect(r.alerts, isEmpty);
      // Vẫn PHẢI chốt trạng thái để lần sau so sánh được.
      expect(r.newCategory, WeatherCategory.cloudy);
    });

    test('trời u ám ⇒ KHÔNG báo gì', () {
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(804),
        env: EnvChange.none,
        now: _now,
      );
      expect(r.alerts, isEmpty);
    });

    test('trời nắng ⇒ KHÔNG báo gì', () {
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(800),
        env: EnvChange.none,
        now: _now,
      );
      expect(r.alerts, isEmpty);
    });

    test('MƯA NHỎ CÓ lượng mưa đo được ⇒ VẪN báo (thứ cần biết ngay)', () {
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(500),
        env: EnvChange.none,
        observedRain1hMm: 1.2,
        now: _now,
      );
      expect(r.alerts.single.title, contains('Mưa nhỏ'));
    });

    test('DÔNG ⇒ VẪN báo', () {
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(202),
        env: EnvChange.none,
        now: _now,
      );
      expect(r.alerts, isNotEmpty);
    });

    test('nhiều mây → u ám khi ĐÃ có trạng thái trước ⇒ vẫn báo như cũ', () {
      // Van chỉ áp cho lần khởi đầu; luồng bình thường không đổi hành vi.
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(804),
        env: EnvChange.none,
        previousPhase: RainPhase.dry,
        previousCategory: WeatherCategory.cloudy,
        now: _now,
      );
      expect(r.alerts.single.title, contains('u ám'));
    });
  });

  group('KHÔNG nói ngược với phân tích mưa (mã mưa nhẹ/vừa cần xác thực)', () {
    test('ca thật 06/08 09:38: pha dry + mã 500 + rain1h 0.16 ⇒ KHÔNG báo', () {
      // Nhật ký thật, CÙNG một chu kỳ: `pha: dry · tình hình: Mưa nhỏ · nowcast
      // bây giờ: 0.00 mm/h · mưa 1h quan trắc: 0.16 mm · mã điều kiện OWM: 500`
      // rồi `ĐÃ BÁO: 🌦️ Mưa nhỏ — "Có mưa nhỏ. Mang theo ô cho chắc chắn."`
      // App tự nói ngược với chính mình, chỉ vì mã điều kiện của OWM.
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(500),
        env: EnvChange.none,
        previousPhase: RainPhase.dry,
        previousCategory: WeatherCategory.cloudy,
        observedRain1hMm: 0.16,
        now: _now,
      );
      expect(r.alerts, isEmpty);
      // GIỮ nhóm cũ: khi có bằng chứng thật, "nhóm đổi" vẫn còn hiệu lực để báo.
      expect(r.newCategory, WeatherCategory.cloudy);
    });

    test('cùng ca đó nhưng phân tích mưa nói SẮP MƯA ⇒ được báo', () {
      final r = sut.call(
        rain: RainStatus(
          phase: RainPhase.rainStartingSoon,
          changeAt: _now.add(const Duration(minutes: 20)),
          minutesUntilChange: 20,
          fromMinutely: true,
        ),
        condition: WeatherCondition.classify(500),
        env: EnvChange.none,
        previousPhase: RainPhase.rainStartingSoon,
        previousCategory: WeatherCategory.cloudy,
        previousChangeAt: _now.add(const Duration(minutes: 20)),
        observedRain1hMm: 0.16,
        now: _now,
      );
      expect(
        r.alerts.map((a) => a.title),
        contains(contains('Mưa nhỏ')),
      );
      expect(r.newCategory, WeatherCategory.lightRain);
    });

    test('MƯA TO khi trời khô ⇒ VẪN báo (nhóm nguy hiểm không bị chặn)', () {
      final r = sut.call(
        rain: const RainStatus.dry(),
        condition: WeatherCondition.classify(502),
        env: EnvChange.none,
        previousPhase: RainPhase.dry,
        previousCategory: WeatherCategory.cloudy,
        now: _now,
      );
      expect(r.alerts.single.title, contains('Mưa to'));
    });
  });
}
