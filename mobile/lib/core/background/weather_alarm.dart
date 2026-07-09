import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../database/app_database.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'weather_check.dart';

/// ID alarm kiểm tra thời tiết (khác các ID bản tin 1005/1006 và ID ghi chú).
const int kWeatherAlarmId = 2001;

/// Lớp DỰ PHÒNG (chỉ dùng khi TẮT foreground service): alarm exact tự đặt lại
/// mỗi chu kỳ. Alarm `exact + allowWhileIdle` bắn được cả trong Doze → đảm bảo
/// dữ liệu vẫn cập nhật khi màn hình tắt/ban đêm mà không cần thông báo thường
/// trực. Khi foreground service BẬT, alarm này bị hủy (xem `applyBackground
/// Triggers` trong main.dart) để tránh 2 lớp cùng đá máy dậy gây nóng.
///
/// One-shot không tự lặp nên [weatherAlarmCallback] phải re-arm mốc kế tiếp.
///
/// Neo mốc kế tiếp theo KHUNG GIỜ HOẠT ĐỘNG: nếu hiện đang TRONG khung → chu kỳ
/// bình thường (`now + interval`); nếu NGOÀI khung → nhảy thẳng tới giờ MỞ khung
/// kế tiếp (ví dụ 5:00 sáng) để không đá CPU dậy vô ích suốt đêm.
Future<void> scheduleWeatherAlarm() async {
  final now = DateTime.now();
  final DateTime fireAt;
  if (await isWithinActiveHours(now)) {
    final interval = await BackgroundPrefsStore().intervalMinutes();
    fireAt = now.add(Duration(minutes: interval));
  } else {
    fireAt = await nextActiveWindowStart(now);
  }
  await AndroidAlarmManager.oneShotAt(
    fireAt,
    kWeatherAlarmId,
    weatherAlarmCallback,
    exact: true,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}

/// Huỷ alarm dự phòng (khi cần).
Future<void> cancelWeatherAlarm() =>
    AndroidAlarmManager.cancel(kWeatherAlarmId);

@pragma('vm:entry-point')
void weatherAlarmCallback() {
  _run();
}

Future<void> _run() async {
  try {
    await _reassertNotes();
  } catch (_) {}
  // Ngoài khung giờ hoạt động → KHÔNG lấy dữ liệu (mát máy, tiết kiệm quota).
  // Vẫn re-arm bên dưới, và mốc kế tiếp sẽ neo vào giờ mở khung.
  try {
    if (await isWithinActiveHours(DateTime.now())) {
      await runWeatherCheck();
    }
  } catch (_) {}
  // Re-arm cho chu kỳ kế tiếp (one-shot không tự lặp). Alarm exact là BACKSTOP
  // thường trực (chạy cả khi FG bật) → luôn tự re-arm. Guard quota trong
  // runWeatherCheck khử gọi API trùng với FG tick nên không tốn thêm hạn mức.
  try {
    await scheduleWeatherAlarm();
  } catch (_) {}
}

Future<void> _reassertNotes() async {
  final db = AppDatabase();
  try {
    await reassertNoteNotifications(db, NotificationService());
  } finally {
    await db.close();
  }
}
