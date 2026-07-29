import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'cycle_lock.dart';
import 'weather_check.dart';

/// ID service foreground (bất kỳ, cố định).
const int kForegroundServiceId = 256;

/// Foreground service (LỚP CHÍNH giữ app sống liên tục): hiển thị một thông báo
/// thường trực và chạy `runWeatherCheck` mỗi chu kỳ — kể cả khi màn hình tắt /
/// trong Doze (nhờ wakelock). Thông báo thường trực được biến thành widget hữu
/// ích: cập nhật nhiệt độ + tình hình hiện tại mỗi chu kỳ.
///
/// Có thể TẮT trong Settings; khi đó alarm exact + WorkManager lo việc cập nhật.
@pragma('vm:entry-point')
void foregroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_WeatherTaskHandler());
}

class _WeatherTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await AppLog.i(LogSource.fg, LogTags.service, 'foreground service khởi động');
    await _tick();
  }

  // Gọi mỗi interval theo eventAction.repeat.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await AppLog.w(LogSource.fg, LogTags.service, 'foreground service DỪNG');
    await AppLog.flush();
  }

  Future<void> _tick() async {
    const src = LogSource.fg;
    await AppLog.i(src, LogTags.cycle, 'tick foreground service');

    final withinWindow = await isWithinActiveHours(DateTime.now());
    if (!withinWindow) {
      // Ngoài khung giờ: KHÔNG mở DB, KHÔNG lấy dữ liệu (mát máy, tiết kiệm
      // quota) nhưng VẪN cập nhật thông báo thường trực để nó nói thật là đang
      // ngủ — trước đây nó đóng băng ở text tối hôm trước, trông y như app chết.
      await AppLog.i(
          src, LogTags.window, 'ngoài khung giờ hoạt động → không lấy dữ liệu');
      await _updateOutsideWindowNotification();
      return;
    }

    try {
      // TOÀN BỘ phần dùng DB nằm TRONG cycle lock — kể cả re-assert ghi chú.
      // Nếu chỉ khoá riêng weather check thì hai isolate vẫn truy vấn cùng file
      // SQLite ở bước re-assert. Bị bỏ lượt cũng không sao: lớp đang giữ lock
      // cũng chạy đúng các bước này.
      final data = await CycleLock.runGuarded(src, () async {
        // Một AppDatabase DUY NHẤT cho cả tick (re-assert ghi chú + weather
        // check) thay vì hai handle như trước — bớt isolate DB, bớt tranh chấp.
        final db = AppDatabase();
        try {
          // Re-assert ghim ghi chú TRƯỚC: khi FG là lớp duy nhất còn chạy, đây
          // là nơi duy nhất hồi phục ghim sau reboot / "Xoá tất cả".
          try {
            await reassertNoteNotifications(db, NotificationService());
          } catch (e, st) {
            await AppLog.e(src, LogTags.db, 'lỗi re-assert ghim ghi chú',
                error: e, stack: st);
          }
          return await runWeatherCheck(source: src, db: db);
        } finally {
          try {
            await db.close();
          } catch (e, st) {
            await AppLog.e(src, LogTags.db, 'lỗi đóng DB', error: e, stack: st);
          }
        }
      });

      if (data != null) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'KatoAssistant đang theo dõi thời tiết',
          notificationText: foregroundStatusText(data),
        );
      }
    } catch (e, st) {
      // Nuốt để service không chết, nhưng GHI LẠI — trước đây lỗi ở đây biến
      // mất hoàn toàn, khiến "app không cập nhật" không thể chẩn đoán.
      await AppLog.e(src, LogTags.cycle, 'lỗi trong tick foreground service',
          error: e, stack: st);
    }
  }

  /// Thông báo thường trực khi đang ngoài khung giờ hoạt động — nói rõ app đang
  /// ngủ theo cài đặt, không phải bị lỗi.
  Future<void> _updateOutsideWindowNotification() async {
    try {
      final store = BackgroundPrefsStore();
      final start = await store.activeStartMinutes();
      final end = await store.activeEndMinutes();
      FlutterForegroundTask.updateService(
        notificationTitle: 'KatoAssistant đang nghỉ',
        notificationText: 'Ngoài khung giờ hoạt động '
            '(${_hhmm(start)}–${_hhmm(end)}) · sẽ cập nhật lại từ ${_hhmm(start)}',
      );
    } catch (_) {
      // Không cập nhật được thông báo thì cứ để nguyên — không đáng làm chết tick.
    }
  }

  static String _hhmm(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Khởi tạo cấu hình service (channel + tuỳ chọn task). Gọi trước khi start.
///
/// [intervalMinutes] = chu kỳ lặp (mặc định [AppConfig.backgroundIntervalMinutes]).
/// KHÔNG bật `allowWifiLock` (giữ WiFi radio thức liên tục gây nóng/tốn pin mà
/// không cần thiết). Giữ `allowWakeLock` vì cần CPU tỉnh để chạy tick trong Doze.
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

/// Bật service.
///
/// [allowRestart] = true (mặc định) → service đang chạy thì restart để áp cấu
/// hình mới (dùng khi người dùng đổi chu kỳ trong Settings).
///
/// Đặt `false` khi gọi từ isolate NỀN (alarm): `restartService()` reset pha lặp
/// của FG về đúng thời điểm gọi, làm FG và alarm tick cùng lúc mãi mãi → tranh
/// chấp DB + thông báo trùng. Từ nền ta chỉ muốn start khi service đã chết.
Future<void> startWeatherForegroundService({bool allowRestart = true}) async {
  final interval = await BackgroundPrefsStore().intervalMinutes();
  initWeatherForegroundService(intervalMinutes: interval);
  if (await FlutterForegroundTask.isRunningService) {
    if (!allowRestart) return;
    await FlutterForegroundTask.restartService();
    return;
  }
  await FlutterForegroundTask.startService(
    serviceId: kForegroundServiceId,
    notificationTitle: 'KatoAssistant đang theo dõi thời tiết',
    notificationText: 'Đang cập nhật tình hình thời tiết…',
    callback: foregroundStartCallback,
  );
}

/// Tắt service (gỡ thông báo thường trực).
Future<void> stopWeatherForegroundService() async {
  await FlutterForegroundTask.stopService();
}
