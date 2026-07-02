import 'package:shared_preferences/shared_preferences.dart';

import '../../weather/domain/entities/rain_status.dart';
import '../../weather/domain/entities/weather_condition.dart';

/// Lưu trạng thái cảnh báo lần trước (SharedPreferences) để chống spam.
/// Dùng được ở cả background isolate (tự đọc SharedPreferences riêng).
class AlertStateStore {
  static const _kPhase = 'alert_last_rain_phase';
  static const _kCategory = 'alert_last_condition_category';
  static const _kEnvNotified = 'alert_env_notified';
  static const _kChangeAt = 'alert_last_change_at';

  Future<
      ({
        RainPhase? phase,
        WeatherCategory? category,
        DateTime? changeAt,
        bool envNotified,
      })> read() async {
    final prefs = await SharedPreferences.getInstance();
    final changeAtMs = prefs.getInt(_kChangeAt);
    return (
      phase: _enumOrNull(prefs.getInt(_kPhase), RainPhase.values),
      category: _enumOrNull(prefs.getInt(_kCategory), WeatherCategory.values),
      changeAt: changeAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(changeAtMs)
          : null,
      envNotified: prefs.getBool(_kEnvNotified) ?? false,
    );
  }

  Future<void> write({
    required RainPhase phase,
    required WeatherCategory category,
    DateTime? changeAt,
    required bool envNotified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPhase, phase.index);
    await prefs.setInt(_kCategory, category.index);
    await prefs.setBool(_kEnvNotified, envNotified);
    if (changeAt != null) {
      await prefs.setInt(_kChangeAt, changeAt.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kChangeAt);
    }
  }

  static T? _enumOrNull<T>(int? idx, List<T> values) =>
      (idx != null && idx >= 0 && idx < values.length) ? values[idx] : null;
}
