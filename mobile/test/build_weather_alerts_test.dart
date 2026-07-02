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
}
