import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/alerts/domain/usecases/build_weather_alerts.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';
import 'package:katocast/features/weather/domain/usecases/detect_env_change.dart';

/// Điều kiện mặc định (trời quang) để cô lập từng nhánh test.
final _clear = WeatherCondition.classify(800);

void main() {
  const sut = BuildWeatherAlerts();

  test('khô → sắp mưa ⇒ phát đúng 1 thông báo bắt đầu mưa', () {
    final r = sut.call(
      rain: const RainStatus(
        phase: RainPhase.rainStartingSoon,
        minutesUntilChange: 20,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.dry,
      previousCategory: WeatherCategory.clear,
    );
    expect(r.alerts.length, 1);
    expect(r.alerts.first.body, contains('20 phút'));
    expect(r.newPhase, RainPhase.rainStartingSoon);
  });

  test('cùng pha & cùng nhóm với lần trước ⇒ KHÔNG phát (chống spam)', () {
    final r = sut.call(
      rain: const RainStatus(
        phase: RainPhase.rainStartingSoon,
        minutesUntilChange: 18,
        fromMinutely: true,
      ),
      condition: _clear,
      env: EnvChange.none,
      previousPhase: RainPhase.rainStartingSoon,
      previousCategory: WeatherCategory.clear,
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
    );
    expect(second.alerts, isEmpty);
  });
}
