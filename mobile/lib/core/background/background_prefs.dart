import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Lưu cài đặt liên quan chạy nền:
/// - bật/tắt foreground service (thông báo thường trực);
/// - chu kỳ cập nhật nền (phút);
/// - khung giờ hoạt động (active hours).
///
/// Thuần → dùng chung main isolate lẫn background isolate lẫn provider.
class BackgroundPrefsStore {
  static const _kForeground = 'fg_service_enabled';
  static const _kInterval = 'bg_interval_min';
  static const _kActiveAllDay = 'bg_active_all_day';
  static const _kActiveStart = 'bg_active_start_min';
  static const _kActiveEnd = 'bg_active_end_min';

  /// Mặc định BẬT: độ tin cậy tối đa (theo lựa chọn người dùng). Người dùng có
  /// thể tắt trong Settings nếu không muốn thông báo thường trực.
  Future<bool> foregroundEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kForeground) ?? true;
  }

  Future<void> setForegroundEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kForeground, value);
  }

  /// Chu kỳ cập nhật nền (phút). Chỉ nhận giá trị trong
  /// [AppConfig.backgroundIntervalOptions]; giá trị lạ rơi về mặc định.
  Future<int> intervalMinutes() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(_kInterval) ?? AppConfig.backgroundIntervalMinutes;
    return AppConfig.backgroundIntervalOptions.contains(v)
        ? v
        : AppConfig.backgroundIntervalMinutes;
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final p = await SharedPreferences.getInstance();
    final v = AppConfig.backgroundIntervalOptions.contains(minutes)
        ? minutes
        : AppConfig.backgroundIntervalMinutes;
    await p.setInt(_kInterval, v);
  }

  /// Có hoạt động cả ngày (24/7) hay không. Mặc định theo
  /// [AppConfig.activeHoursAllDayDefault] (hiện là `false` → giới hạn giờ).
  Future<bool> activeAllDay() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kActiveAllDay) ?? AppConfig.activeHoursAllDayDefault;
  }

  Future<void> setActiveAllDay(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActiveAllDay, value);
  }

  /// Giờ MỞ khung (phút-trong-ngày, 0..1439). Clamp về khoảng hợp lệ.
  Future<int> activeStartMinutes() async {
    final p = await SharedPreferences.getInstance();
    return _clampMinutes(
        p.getInt(_kActiveStart) ?? AppConfig.activeHoursStartDefault);
  }

  Future<void> setActiveStartMinutes(int minutes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kActiveStart, _clampMinutes(minutes));
  }

  /// Giờ ĐÓNG khung (phút-trong-ngày, 0..1439). Clamp về khoảng hợp lệ.
  Future<int> activeEndMinutes() async {
    final p = await SharedPreferences.getInstance();
    return _clampMinutes(
        p.getInt(_kActiveEnd) ?? AppConfig.activeHoursEndDefault);
  }

  Future<void> setActiveEndMinutes(int minutes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kActiveEnd, _clampMinutes(minutes));
  }

  static int _clampMinutes(int m) => m < 0 ? 0 : (m > 1439 ? 1439 : m);
}

/// True nếu [now] nằm trong khung giờ hoạt động (hoặc đang bật cả ngày). Hỗ trợ
/// cả khung qua nửa đêm (start > end, ví dụ 22:00→06:00). Dùng để gate 3 lớp
/// trigger nền — ngoài khung thì KHÔNG lấy dữ liệu.
Future<bool> isWithinActiveHours(DateTime now) async {
  final store = BackgroundPrefsStore();
  if (await store.activeAllDay()) return true;
  final start = await store.activeStartMinutes();
  final end = await store.activeEndMinutes();
  final m = now.hour * 60 + now.minute;
  if (start == end) return true; // khung suy biến = cả ngày (an toàn).
  return start < end ? (m >= start && m < end) : (m >= start || m < end);
}

/// DateTime lần kế tiếp khung giờ MỞ, tính từ [now]. Dùng cho alarm exact
/// backstop re-arm đúng vào giờ mở khung thay vì đá dậy mỗi chu kỳ suốt đêm.
Future<DateTime> nextActiveWindowStart(DateTime now) async {
  final store = BackgroundPrefsStore();
  final start = await store.activeStartMinutes();
  var target = DateTime(now.year, now.month, now.day, start ~/ 60, start % 60);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
  return target;
}
