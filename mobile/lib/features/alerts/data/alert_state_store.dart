import 'package:shared_preferences/shared_preferences.dart';

import '../../weather/domain/entities/rain_status.dart';
import '../../weather/domain/entities/weather_condition.dart';

/// Lưu trạng thái cảnh báo lần trước (SharedPreferences) để chống spam.
/// Dùng được ở cả background isolate (tự đọc SharedPreferences riêng).
class AlertStateStore {
  static const _kPhase = 'alert_last_rain_phase';
  static const _kCategory = 'alert_last_condition_category';
  static const _kEnvNotified = 'alert_env_notified';

  Future<
      ({
        RainPhase? phase,
        WeatherCategory? category,
        bool envNotified,
      })> read() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      phase: _enumOrNull(prefs.getInt(_kPhase), RainPhase.values),
      category: _enumOrNull(prefs.getInt(_kCategory), WeatherCategory.values),
      envNotified: prefs.getBool(_kEnvNotified) ?? false,
    );
  }

  Future<void> write({
    required RainPhase phase,
    required WeatherCategory category,
    required bool envNotified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPhase, phase.index);
    await prefs.setInt(_kCategory, category.index);
    await prefs.setBool(_kEnvNotified, envNotified);
  }

  static T? _enumOrNull<T>(int? idx, List<T> values) =>
      (idx != null && idx >= 0 && idx < values.length) ? values[idx] : null;
}
