import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';
import 'package:katocast/features/weather/domain/usecases/analyze_rain.dart';
import 'package:katocast/features/weather/domain/usecases/build_advisories.dart';

import 'fixtures/fake_weather.dart';

void main() {
  const sut = BuildAdvisories();

  List<Advisory> run(data, {RainStatus? rain}) {
    final c = data.current;
    final condition =
        WeatherCondition.classify(c.conditionId, rainMmH: c.rain1h);
    return sut.call(current: c, condition: condition, rain: rain);
  }

  test('quang mây UV thấp: không có lưu ý UV', () {
    final items = run(clearScenario());
    expect(items.any((a) => a.kind == AdvisoryKind.uv), isFalse);
  });

  test('UV cực cao: có lưu ý UV', () {
    final items = run(highUvScenario());
    expect(items.any((a) => a.kind == AdvisoryKind.uv), isTrue);
  });

  test('ẩm cao + gió mạnh: có cả lưu ý độ ẩm và gió', () {
    final items = run(humidWindyScenario());
    expect(items.any((a) => a.kind == AdvisoryKind.humidity), isTrue);
    expect(items.any((a) => a.kind == AdvisoryKind.wind), isTrue);
  });

  test('đang mưa: có lưu ý mưa', () {
    final data = rainingNowScenario();
    final rain = const AnalyzeRain().call(data, now: fakeNow);
    final items = run(data, rain: rain);
    expect(items.any((a) => a.kind == AdvisoryKind.rain), isTrue);
  });

  test('bão lớn: có lưu ý tình hình (advice không rỗng)', () {
    final items = run(stormScenario());
    expect(items.any((a) => a.kind == AdvisoryKind.condition), isTrue);
  });
}
