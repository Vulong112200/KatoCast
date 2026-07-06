import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/alerts/domain/usecases/build_daily_digest.dart';

import 'fixtures/fake_weather.dart';

void main() {
  const sut = BuildDailyDigest();

  test('quang mây: tiêu đề có emoji nắng + nhiệt độ, thân có UV & cập nhật', () {
    final d = sut.call(clearScenario(), now: fakeNow);
    expect(d.title, contains('°C'));
    expect(d.title, contains('☀️')); // conditionId 800 = nắng
    expect(d.body, contains('UV'));
    expect(d.body, contains('Cập nhật lúc'));
    expect(d.body, contains('Cảm giác như'));
  });

  test('đang mưa: thân bản tin nêu "đang có mưa"', () {
    final d = sut.call(rainingNowScenario(), now: fakeNow);
    expect(d.body.toLowerCase(), contains('đang có mưa'));
  });

  test('sắp mưa: thân bản tin nêu giờ mưa dự kiến (12:20)', () {
    final d = sut.call(rainSoonScenario(), now: fakeNow);
    expect(d.body, contains('Dự kiến mưa lúc 12:20'));
  });

  test('hi/lo lấy từ 24h hourly', () {
    final d = sut.call(clearScenario(), now: fakeNow);
    expect(d.body, contains('Hôm nay khoảng'));
  });

  test('UV cực cao: bản tin nêu mức "Cực kỳ cao"', () {
    final d = sut.call(highUvScenario(), now: fakeNow);
    expect(d.body, contains('Cực kỳ cao'));
  });
}
