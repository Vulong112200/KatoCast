import 'background_prefs.dart';
import 'background_worker.dart';
import 'foreground_service.dart';
import 'weather_alarm.dart';

/// Điều phối các lớp chạy nền sao cho **chỉ MỘT cơ chế** drive `runWeatherCheck`
/// tại một thời điểm — tránh việc 3 lớp (foreground service + alarm exact +
/// WorkManager) cùng đánh thức máy mỗi chu kỳ gây nóng/tốn pin.
///
/// Quy tắc:
/// - **Foreground service BẬT** (mặc định): foreground service là lớp CHÍNH
///   (cập nhật liên tục kể cả Doze nhờ wakelock) + **giữ alarm exact chạy song
///   song làm BACKSTOP** — hồi phục khi service bị Doze/OEM giết (mà chưa bị
///   force-stop). HỦY WorkManager để không thành 3 lớp (alarm đã đủ backstop +
///   tự re-assert ghim ghi chú). Guard quota trong `runWeatherCheck` khử gọi
///   API trùng giữa FG tick và alarm nên backstop thêm rất ít nhiệt.
/// - **Foreground service TẮT**: không có thông báo thường trực → dùng alarm
///   exact + WorkManager làm đường tin cậy (backstop). DỪNG foreground service.
///
/// LƯU Ý: trên OEM diệt tiến trình mạnh (Nubia/MyOS, Xiaomi/HyperOS…), khi
/// người dùng VUỐT TẮT app, OS force-stop → hủy sạch mọi alarm; không cơ chế
/// nào cứu được ngoài việc người dùng bật "Tự khởi động" + "Không giới hạn pin"
/// (xem onboarding trong `main.dart`).
///
/// Gọi ở bootstrap và mỗi khi người dùng đổi cài đặt nền (bật/tắt FG, đổi chu
/// kỳ). Idempotent + bọc try để một plugin lỗi trên máy nào đó không làm hỏng
/// các lớp còn lại.
Future<void> applyBackgroundTriggers() async {
  final foregroundOn = await BackgroundPrefsStore().foregroundEnabled();

  if (foregroundOn) {
    // FG chính + alarm exact backstop chạy song song. Chỉ tắt WorkManager.
    try {
      await BackgroundScheduler.cancel();
    } catch (_) {}
    try {
      await startWeatherForegroundService();
    } catch (_) {}
    try {
      await scheduleWeatherAlarm();
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
