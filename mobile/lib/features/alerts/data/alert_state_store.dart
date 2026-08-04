import 'package:shared_preferences/shared_preferences.dart';

import '../../weather/domain/entities/rain_status.dart';
import '../../weather/domain/entities/weather_condition.dart';

/// Lưu trạng thái cảnh báo lần trước (SharedPreferences) để chống spam.
///
/// Đây là cơ chế chống-báo-trùng DUY NHẤT cho cảnh báo thời tiết, và nó phải
/// đúng qua RANH GIỚI ISOLATE: foreground service, alarm exact và WorkManager là
/// ba isolate khác nhau nhưng cùng đọc/ghi trạng thái này.
///
/// `SharedPreferences.getInstance()` trả về một bản cache trong bộ nhớ RIÊNG của
/// từng isolate, chỉ nạp từ đĩa ở lần khởi tạo đầu. Isolate của foreground
/// service sống hàng giờ, nên nếu không `reload()` thì nó **không bao giờ thấy**
/// những gì isolate alarm đã ghi — và cứ phát lại cảnh báo dựa trên `notifiedAt`
/// cũ. Đó chính là lý do một tin bị thông báo nhiều lần. Vì vậy [read] LUÔN
/// `reload()` trước khi đọc.
class AlertStateStore {
  static const _kPhase = 'alert_last_rain_phase';
  static const _kCategory = 'alert_last_condition_category';
  static const _kEnvNotified = 'alert_env_notified';
  static const _kChangeAt = 'alert_last_change_at';
  static const _kNotifiedAt = 'alert_last_notified_at';
  static const _kUpdatedAt = 'alert_state_updated_at';

  /// Trạng thái cũ hơn ngưỡng này thì KHÔNG còn dùng để so sánh.
  ///
  /// Vì sao cần: chống-spam dựa trên "so với lần trước", giả định các chu kỳ nối
  /// tiếp nhau vài phút một. Khi tiến trình bị OEM giết hàng giờ, giả định đó
  /// sụp. Nhật ký thật cho thấy lúc 12:24 hôm sau app vẫn so với trạng thái ghi
  /// từ **20:57 hôm trước** — dẫn tới hai kiểu sai: hoặc im lặng vì "pha không
  /// đổi" dù đã 15 tiếng, hoặc phát "Trời đã tạnh mưa" cho một cơn mưa từ đêm
  /// qua. Quá ngưỡng này thì coi như KHỞI ĐẦU MỚI: cảnh báo hiện tại được phát
  /// lại đúng theo tình hình thật.
  static const Duration maxAge = Duration(hours: 2);

  Future<
      ({
        RainPhase? phase,
        WeatherCategory? category,
        DateTime? changeAt,
        DateTime? notifiedAt,
        bool envNotified,
        Duration? age,
        bool expired,
      })> read() async {
    final prefs = await SharedPreferences.getInstance();
    // BẮT BUỘC: nạp lại từ đĩa để thấy trạng thái do isolate khác ghi.
    await prefs.reload();

    final updatedAt = _dateOrNull(prefs.getInt(_kUpdatedAt));
    final age = updatedAt == null ? null : DateTime.now().difference(updatedAt);
    // Bản ghi từ phiên bản cũ (chưa có mốc) vẫn dùng được — không có cơ sở để
    // kết luận nó cũ, và một lần so sánh dư an toàn hơn một lần báo trùng.
    final expired = age != null && age > maxAge;

    if (expired) {
      return (
        phase: null,
        category: null,
        changeAt: null,
        notifiedAt: null,
        envNotified: false,
        age: age,
        expired: true,
      );
    }

    return (
      phase: _enumOrNull(prefs.getInt(_kPhase), RainPhase.values),
      category: _enumOrNull(prefs.getInt(_kCategory), WeatherCategory.values),
      changeAt: _dateOrNull(prefs.getInt(_kChangeAt)),
      notifiedAt: _dateOrNull(prefs.getInt(_kNotifiedAt)),
      envNotified: prefs.getBool(_kEnvNotified) ?? false,
      age: age,
      expired: false,
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
    await prefs.setInt(_kUpdatedAt, DateTime.now().millisecondsSinceEpoch);
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
