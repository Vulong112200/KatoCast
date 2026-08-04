import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/alerts/data/alert_state_store.dart';
import 'package:katocast/features/weather/domain/entities/rain_status.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sut = AlertStateStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trip: ghi rồi đọc lại đủ trường', () async {
    final changeAt = DateTime(2026, 7, 29, 14, 30);
    final notifiedAt = DateTime(2026, 7, 29, 14, 0);
    await sut.write(
      phase: RainPhase.rainStartingSoon,
      category: WeatherCategory.cloudy,
      changeAt: changeAt,
      notifiedAt: notifiedAt,
      envNotified: true,
    );

    final read = await sut.read();
    expect(read.expired, isFalse);
    expect(read.phase, RainPhase.rainStartingSoon);
    expect(read.category, WeatherCategory.cloudy);
    expect(read.changeAt, changeAt);
    expect(read.notifiedAt, notifiedAt);
    expect(read.envNotified, isTrue);
  });

  test('chưa từng ghi ⇒ mọi trường null, KHÔNG bị coi là quá hạn', () async {
    final read = await sut.read();
    expect(read.expired, isFalse);
    expect(read.phase, isNull);
    expect(read.age, isNull);
  });

  test('trạng thái QUÁ CŨ ⇒ expired, trả về như chưa có gì', () async {
    // Mô phỏng đúng ca thật: app bị OEM giết, trạng thái ghi từ 20:57 hôm trước
    // vẫn còn nằm đó tới trưa hôm sau.
    final stale = DateTime.now().subtract(AlertStateStore.maxAge * 2);
    SharedPreferences.setMockInitialValues({
      'alert_last_rain_phase': RainPhase.raining.index,
      'alert_last_condition_category': WeatherCategory.lightRain.index,
      'alert_env_notified': true,
      'alert_state_updated_at': stale.millisecondsSinceEpoch,
    });

    final read = await sut.read();
    expect(read.expired, isTrue);
    expect(read.phase, isNull,
        reason: 'không được so sánh với pha từ nhiều giờ trước');
    expect(read.category, isNull);
    expect(read.notifiedAt, isNull);
    expect(read.envNotified, isFalse);
    expect(read.age!.inHours, greaterThanOrEqualTo(AlertStateStore.maxAge.inHours));
  });

  test('trạng thái còn trong hạn ⇒ vẫn dùng để so sánh', () async {
    final fresh = DateTime.now().subtract(const Duration(minutes: 10));
    SharedPreferences.setMockInitialValues({
      'alert_last_rain_phase': RainPhase.raining.index,
      'alert_last_condition_category': WeatherCategory.lightRain.index,
      'alert_state_updated_at': fresh.millisecondsSinceEpoch,
    });

    final read = await sut.read();
    expect(read.expired, isFalse);
    expect(read.phase, RainPhase.raining);
  });

  test('bản ghi từ phiên bản CŨ (không có mốc) vẫn được dùng', () async {
    // Không có `alert_state_updated_at` → không có cơ sở kết luận là cũ; một lần
    // so sánh dư an toàn hơn một lần báo trùng.
    SharedPreferences.setMockInitialValues({
      'alert_last_rain_phase': RainPhase.rainStartingSoon.index,
      'alert_last_condition_category': WeatherCategory.cloudy.index,
    });

    final read = await sut.read();
    expect(read.expired, isFalse);
    expect(read.phase, RainPhase.rainStartingSoon);
    expect(read.age, isNull);
  });

  test('write cập nhật mốc ⇒ trạng thái quá hạn trở lại còn hạn', () async {
    final stale = DateTime.now().subtract(AlertStateStore.maxAge * 2);
    SharedPreferences.setMockInitialValues({
      'alert_last_rain_phase': RainPhase.raining.index,
      'alert_state_updated_at': stale.millisecondsSinceEpoch,
    });
    expect((await sut.read()).expired, isTrue);

    await sut.write(
      phase: RainPhase.dry,
      category: WeatherCategory.clear,
      envNotified: false,
    );

    final read = await sut.read();
    expect(read.expired, isFalse);
    expect(read.phase, RainPhase.dry);
  });
}
