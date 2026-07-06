import 'background_prefs.dart';
import 'background_worker.dart';
import 'foreground_service.dart';
import 'weather_alarm.dart';

/// Điều phối các lớp chạy nền sao cho **chỉ MỘT cơ chế** drive `runWeatherCheck`
/// tại một thời điểm — tránh việc 3 lớp (foreground service + alarm exact +
/// WorkManager) cùng đánh thức máy mỗi chu kỳ gây nóng/tốn pin.
///
/// Quy tắc:
/// - **Foreground service BẬT** (mặc định): dùng foreground service làm lớp duy
///   nhất (cập nhật liên tục kể cả Doze nhờ wakelock của service). HỦY alarm
///   exact + WorkManager để không trùng.
/// - **Foreground service TẮT**: không có thông báo thường trực → dùng alarm
///   exact + WorkManager làm đường tin cậy (backstop). DỪNG foreground service.
///
/// Gọi ở bootstrap và mỗi khi người dùng đổi cài đặt nền (bật/tắt FG, đổi chu
/// kỳ). Idempotent + bọc try để một plugin lỗi trên máy nào đó không làm hỏng
/// các lớp còn lại.
Future<void> applyBackgroundTriggers() async {
  final foregroundOn = await BackgroundPrefsStore().foregroundEnabled();

  if (foregroundOn) {
    // Lớp duy nhất: foreground service. Tắt hai lớp trùng.
    try {
      await cancelWeatherAlarm();
    } catch (_) {}
    try {
      await BackgroundScheduler.cancel();
    } catch (_) {}
    try {
      await startWeatherForegroundService();
    } catch (_) {}
  } else {
    // Không thông báo thường trực → alarm exact + WorkManager lo cập nhật.
    try {
      await stopWeatherForegroundService();
    } catch (_) {}
    try {
      await BackgroundScheduler.initialize();
    } catch (_) {}
    try {
      await scheduleWeatherAlarm();
    } catch (_) {}
  }
}
