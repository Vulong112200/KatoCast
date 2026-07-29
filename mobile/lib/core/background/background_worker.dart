import 'package:workmanager/workmanager.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'cycle_lock.dart';
import 'weather_alarm.dart';
import 'weather_check.dart';

const String kWeatherCheckTask = 'katocast.weatherCheck';

/// Đăng ký task định kỳ — lớp nền có lịch do **hệ điều hành** giữ.
///
/// WorkManager bị Android hoãn/gộp periodic work trong Doze và TỐI THIỂU 15', nên
/// nó không thay được foreground service cho việc cập nhật kịp thời. Nhưng nó có
/// một điểm mạnh không lớp nào khác có: lịch nằm trong JobScheduler của HĐH, nên
/// **sống sót khi chuỗi alarm one-shot do app tự re-arm bị đứt**. Vì vậy nay nó
/// LUÔN được bật (kể cả khi foreground service bật) làm lưới an toàn cuối cùng —
/// `CycleLock` lo việc không chạy chồng.
class BackgroundScheduler {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    final interval = await BackgroundPrefsStore().intervalMinutes();
    // WorkManager tối thiểu 15'.
    final freq = interval < 15 ? 15 : interval;
    await Workmanager().registerPeriodicTask(
      kWeatherCheckTask,
      kWeatherCheckTask,
      frequency: Duration(minutes: freq),
      constraints: Constraints(networkType: NetworkType.connected),
      // `update`: áp cấu hình mới lên task đã đăng ký từ lần cài trước.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Hủy task định kỳ.
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
    const src = LogSource.worker;
    await AppLog.i(src, LogTags.cycle, 'WorkManager chạy');

    try {
      // TOÀN BỘ phần dùng DB trong cycle lock (kể cả re-assert ghi chú) để không
      // truy vấn cùng file SQLite lúc foreground service/alarm đang chạy.
      await CycleLock.runGuarded(src, () async {
        final db = AppDatabase();
        try {
          // Ghi chú ghim: re-assert TRƯỚC — hồi phục sau reboot / "Xoá tất cả"
          // kể cả khi không có vị trí (guard coords của weather không chặn).
          try {
            await reassertNoteNotifications(db, NotificationService());
          } catch (e, st) {
            await AppLog.e(src, LogTags.db, 'lỗi re-assert ghim ghi chú',
                error: e, stack: st);
          }

          if (!await isWithinActiveHours(DateTime.now())) {
            await AppLog.i(src, LogTags.window,
                'ngoài khung giờ hoạt động → không lấy dữ liệu');
            return;
          }
          await runWeatherCheck(source: src, db: db);
        } finally {
          try {
            await db.close();
          } catch (e, st) {
            await AppLog.e(src, LogTags.db, 'lỗi đóng DB', error: e, stack: st);
          }
        }
      });

      // Lưới an toàn: nếu chuỗi alarm one-shot đã ĐỨT (OEM giết tiến trình giữa
      // đêm) thì WorkManager là nơi duy nhất còn chạy để dựng lại nó. Chỉ dựng
      // khi thật sự quá hạn — arm lại vô điều kiện sẽ đẩy lùi alarm đang sắp nổ.
      try {
        final status = await weatherAlarmChainStatus();
        if (status.overdue) {
          await AppLog.w(
            src,
            LogTags.arm,
            'chuỗi alarm ĐỨT → WorkManager dựng lại',
            data: {
              'mốc đã đặt': status.expectedAt?.toLocal().toString() ?? 'chưa có',
            },
          );
          await scheduleWeatherAlarm(source: src);
        }
      } catch (e, st) {
        await AppLog.e(src, LogTags.arm, 'không dựng lại được chuỗi alarm',
            error: e, stack: st);
      }
    } catch (e, st) {
      await AppLog.e(src, LogTags.cycle, 'lỗi trong lượt WorkManager',
          error: e, stack: st);
    } finally {
      await AppLog.flush();
    }
    return true;
  });
}
