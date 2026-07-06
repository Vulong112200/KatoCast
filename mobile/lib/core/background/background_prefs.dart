import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Lưu cài đặt liên quan chạy nền:
/// - bật/tắt foreground service (thông báo thường trực);
/// - chu kỳ cập nhật nền (phút).
///
/// Thuần → dùng chung main isolate lẫn background isolate lẫn provider.
class BackgroundPrefsStore {
  static const _kForeground = 'fg_service_enabled';
  static const _kInterval = 'bg_interval_min';

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
}
