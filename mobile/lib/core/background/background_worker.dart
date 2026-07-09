import 'package:workmanager/workmanager.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../database/app_database.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'weather_check.dart';

const String kWeatherCheckTask = 'katocast.weatherCheck';

/// Đăng ký task định kỳ — chỉ là đường TIN CẬY khi TẮT foreground service.
///
/// WorkManager bị Android hoãn/gộp periodic work trong Doze và TỐI THIỂU 15'
/// (giá trị <15 sẽ bị kẹp về 15). Khi foreground service bật, task này bị hủy
/// (xem `applyBackgroundTriggers` trong main.dart) để tránh trùng lặp gây nóng.
/// Cả các lớp đều đổ về `runWeatherCheck` (có guard quota).
class BackgroundScheduler {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    final interval = await BackgroundPrefsStore().intervalMinutes();
    // WorkManager tối thiểu 15' — chu kỳ ngắn hơn chỉ có tác dụng khi foreground
    // service bật (lúc đó WorkManager đã bị hủy nên không mâu thuẫn).
    final freq = interval < 15 ? 15 : interval;
    await Workmanager().registerPeriodicTask(
      kWeatherCheckTask,
      kWeatherCheckTask,
      frequency: Duration(minutes: freq),
      constraints: Constraints(networkType: NetworkType.connected),
      // `update`: áp cấu hình mới lên task đã đăng ký từ lần cài trước (với
      // `keep`, các thay đổi ở đây sẽ không có hiệu lực trên máy đã cài).
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Hủy task định kỳ (khi bật foreground service → chỉ cần 1 lớp trigger).
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kWeatherCheckTask);
  }

  /// Tiện ích debug: chạy ngay 1 lần để test notification.
  static Future<void> runOnceNow() async {
    await Workmanager().registerOneOffTask(
      '$kWeatherCheckTask.once',
      kWeatherCheckTask,
    );
  }
}

/// Entry-point chạy trong background isolate. KHÔNG dùng Riverpod ở đây —
/// isolate này không chia sẻ state với main isolate, nên tự dựng dependency.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kWeatherCheckTask) return true;
    // Ghi chú ghim: re-assert TRƯỚC (try riêng, DB riêng) — hồi phục sau
    // reboot/"Xoá tất cả" kể cả khi không có vị trí (guard coords của weather
    // không được chặn bước này).
    try {
      await _reassertNotes();
    } catch (_) {}
    try {
      // Ngoài khung giờ hoạt động → bỏ qua lấy dữ liệu (mát máy, tiết kiệm quota).
      if (await isWithinActiveHours(DateTime.now())) {
        await runWeatherCheck();
      }
    } catch (_) {
      // Nuốt lỗi để WorkManager không retry dồn dập; lần sau sẽ check lại.
    }
    return true;
  });
}

Future<void> _reassertNotes() async {
  final db = AppDatabase();
  try {
    await reassertNoteNotifications(db, NotificationService());
  } finally {
    await db.close();
  }
}
