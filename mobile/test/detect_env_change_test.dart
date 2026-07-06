import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/usecases/detect_env_change.dart';

import 'fixtures/fake_weather.dart';

void main() {
  const sut = DetectEnvChange();

  test('nhiệt độ tăng vọt trong 3h tới ⇒ hasStrongChange', () {
    // envChangeScenario: 25°C → +3°C/giờ, giờ thứ 2 (trong window 3h) đã +6°C.
    final env = sut.call(envChangeScenario());
    expect(env.hasStrongChange, isTrue);
    expect(env.tempDeltaC, greaterThanOrEqualTo(5.0));
  });

  test('thời tiết ổn định ⇒ không có thay đổi mạnh', () {
    final env = sut.call(clearScenario());
    expect(env.hasStrongChange, isFalse);
  });

  test('không có hourly ⇒ EnvChange.none', () {
    final env = sut.call(fakeWeather());
    expect(env.hasStrongChange, isFalse);
    expect(env.tempDeltaC, 0);
  });
}
