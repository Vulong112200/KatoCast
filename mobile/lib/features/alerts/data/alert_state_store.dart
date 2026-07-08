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
  static const _kNotifiedAt = 'alert_last_notified_at';

  Future<
      ({
        RainPhase? phase,
        WeatherCategory? category,
        DateTime? changeAt,
        DateTime? notifiedAt,
        bool envNotified,
      })> read() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      phase: _enumOrNull(prefs.getInt(_kPhase), RainPhase.values),
      category: _enumOrNull(prefs.getInt(_kCategory), WeatherCategory.values),
      changeAt: _dateOrNull(prefs.getInt(_kChangeAt)),
      notifiedAt: _dateOrNull(prefs.getInt(_kNotifiedAt)),
      envNotified: prefs.getBool(_kEnvNotified) ?? false,
    );
  }

  Future<void> write({
    required RainPhase phase,
    required WeatherCategory category,
    DateTime? changeAt,
    DateTime? notifiedAt,
    required bool envNotified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPhase, phase.index);
    await prefs.setInt(_kCategory, category.index);
    await prefs.setBool(_kEnvNotified, envNotified);
    await _setDate(prefs, _kChangeAt, changeAt);
    await _setDate(prefs, _kNotifiedAt, notifiedAt);
  }

  static DateTime? _dateOrNull(int? ms) =>
      ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

  static Future<void> _setDate(
    SharedPreferences prefs,
    String key,
    DateTime? value,
  ) async {
    if (value != null) {
      await prefs.setInt(key, value.millisecondsSinceEpoch);
    } else {
      await prefs.remove(key);
    }
  }

  static T? _enumOrNull<T>(int? idx, List<T> values) =>
      (idx != null && idx >= 0 && idx < values.length) ? values[idx] : null;
}
