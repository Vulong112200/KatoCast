import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'weather_check.dart';

/// ID service foreground (bất kỳ, cố định).
const int kForegroundServiceId = 256;

/// Foreground service (LỚP CHÍNH giữ app sống liên tục): hiển thị một thông báo
/// thường trực và chạy `runWeatherCheck` mỗi ~15' — kể cả khi màn hình tắt /
/// trong Doze (nhờ wakelock). Thông báo thường trực được biến thành widget hữu
/// ích: cập nhật nhiệt độ + tình hình hiện tại mỗi chu kỳ.
///
/// Có thể TẮT trong Settings; khi đó vẫn còn alarm exact + WorkManager lo việc
/// cập nhật (nhưng kém liên tục hơn khi bị Doze).
@pragma('vm:entry-point')
void foregroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_WeatherTaskHandler());
}

class _WeatherTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _tick();
  }

  // Gọi mỗi interval theo eventAction.repeat.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  Future<void> _tick() async {
    // Re-assert ghim ghi chú TRƯỚC (DB riêng, try riêng) — khi FG là lớp duy
    // nhất còn chạy, đây là nơi duy nhất hồi phục ghim sau reboot/"Xoá tất cả".
    try {
      await _reassertNotes();
    } catch (_) {}
    // Ngoài khung giờ hoạt động → GIỮ thông báo thường trực nhưng KHÔNG lấy dữ
    // liệu / không cập nhật (mát máy, tiết kiệm quota). Đến giờ mở khung, tick
    // kế tiếp tự cập nhật lại.
    if (!await isWithinActiveHours(DateTime.now())) return;
    try {
      final data = await runWeatherCheck();
      if (data != null) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'KatoAssistant đang theo dõi thời tiết',
          notificationText: foregroundStatusText(data),
        );
      }
    } catch (_) {
      // Nuốt lỗi để service không chết; chu kỳ sau thử lại.
    }
  }

  Future<void> _reassertNotes() async {
    final db = AppDatabase();
    try {
      await reassertNoteNotifications(db, NotificationService());
    } finally {
      await db.close();
    }
  }
}

/// Khởi tạo cấu hình service (channel + tuỳ chọn task). Gọi trước khi start.
///
/// [intervalMinutes] = chu kỳ lặp (mặc định [AppConfig.backgroundIntervalMinutes]).
/// KHÔNG bật `allowWifiLock` (giữ WiFi radio thức liên tục gây nóng/tốn pin mà
/// không cần thiết — mỗi tick chỉ gọi mạng vài giây). Giữ `allowWakeLock` vì
/// cần CPU tỉnh để chạy tick trong Doze; đây là nguồn wakelock DUY NHẤT khi
/// foreground service bật (alarm exact + WorkManager đã tắt để tránh trùng lặp).
void initWeatherForegroundService({
  int intervalMinutes = AppConfig.backgroundIntervalMinutes,
}) {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'weather_foreground',
      channelName: 'Theo dõi thời tiết',
      channelDescription:
          'Giữ app chạy nền để cập nhật thời tiết và cảnh báo mưa kịp thời.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Lặp mỗi chu kỳ nền do người dùng chọn — mili-giây.
      eventAction: ForegroundTaskEventAction.repeat(
        intervalMinutes * 60 * 1000,
      ),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// Bật service (idempotent: đang chạy thì restart để áp cấu hình mới).
Future<void> startWeatherForegroundService() async {
  final interval = await BackgroundPrefsStore().intervalMinutes();
  initWeatherForegroundService(intervalMinutes: interval);
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      serviceId: kForegroundServiceId,
      notificationTitle: 'KatoAssistant đang theo dõi thời tiết',
      notificationText: 'Đang cập nhật tình hình thời tiết…',
      callback: foregroundStartCallback,
    );
  }
}

/// Tắt service (gỡ thông báo thường trực).
Future<void> stopWeatherForegroundService() async {
  await FlutterForegroundTask.stopService();
}
