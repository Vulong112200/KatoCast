import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/notes/data/note_notification_service.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';
import 'cycle_lock.dart';
import 'service_health.dart';
import 'weather_alarm.dart';
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
    // Service sống lại → xoá mốc "đã chết" và gỡ thông báo nhắc mở app, để lớp
    // nền không còn nghĩ app đang im lặng.
    await ForegroundServiceHealth.markAlive();
    await ForegroundServiceHealth.clearNudgeNotification();
    await _tick();
  }

  // Gọi mỗi interval theo eventAction.repeat.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Ghi mốc chết NGAY tại đây (không đợi lớp alarm phát hiện): đây là lần duy
    // nhất app biết chính xác thời điểm service dừng. Android 15+ dừng FGS bằng
    // `onTimeout` khi hết hạn mức thời lượng, và đường đó cũng đi qua `onDestroy`.
    await ForegroundServiceHealth.markDead();
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
        // `await`: bản cũ bỏ trắng Future này nên một lần cập nhật thất bại
        // (service vừa bị hệ thống dừng) trở thành lỗi không ai bắt.
        await FlutterForegroundTask.updateService(
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

    // Lưới an toàn THỨ HAI cho chuỗi alarm (WorkManager là lưới thứ nhất): FG
    // service là lớp chạy đều nhất khi nó còn sống, nên để nó cũng dựng lại
    // chuỗi alarm khi chuỗi đã đứt. Chỉ arm khi THẬT SỰ quá hạn — arm vô điều
    // kiện sẽ đẩy lùi một alarm đang sắp nổ và phá pha lệch nửa chu kỳ.
    try {
      if ((await weatherAlarmChainStatus()).overdue) {
        await AppLog.w(src, LogTags.arm,
            'chuỗi alarm ĐỨT → foreground service dựng lại');
        await scheduleWeatherAlarm(source: src);
      }
    } catch (e, st) {
      await AppLog.e(src, LogTags.arm, 'không dựng lại được chuỗi alarm',
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
      await FlutterForegroundTask.updateService(
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

/// Bật service. **CHỈ được gọi khi app đang hiển thị với người dùng.**
///
/// ⚠️ TUYỆT ĐỐI KHÔNG gọi từ isolate nền (alarm/WorkManager/digest). Từ Android
/// 12 (API 31), start một foreground service khi app ở nền bị hệ thống từ chối,
/// và `flutter_foreground_task` gọi `startForeground()` trong `onStartCommand`
/// **không có try/catch** → `ForegroundServiceStartNotAllowedException` bay lên
/// luồng chính và **giết cả tiến trình**. Nhật ký thật 02/08 ghi đúng 6 lần
/// "thử hồi sinh" rồi im lặng tuyệt đối mỗi lần, và sau đó hệ thống force-stop
/// app khiến mọi alarm + job bị hủy, app đứng im 46 tiếng. Xem
/// [ForegroundServiceHealth] để biết đường hồi phục đúng.
///
/// [allowRestart] = true (mặc định) → service đang chạy thì restart để áp cấu
/// hình mới (dùng khi người dùng đổi chu kỳ trong Settings). Đặt `false` khi chỉ
/// muốn start nếu service đã chết: `restartService()` reset pha lặp của FG về
/// đúng thời điểm gọi, làm FG và alarm tick cùng lúc mãi mãi → tranh chấp DB +
/// thông báo trùng.
///
/// Trả `true` nếu service đang chạy sau lời gọi này.
Future<bool> startWeatherForegroundService({bool allowRestart = true}) async {
  // Service khai báo `foregroundServiceType="location"` (bắt buộc, vì `dataSync`
  // bị Android 15+ cắt sau 6h/24h — xem AndroidManifest). Android 14+ đòi quyền
  // vị trí RUNTIME cho kiểu này: thiếu quyền thì `startForeground` ném
  // SecurityException NGAY TRONG service → sập tiến trình. Nên kiểm tra trước.
  if (!await _hasLocationPermissionForFgs()) {
    await AppLog.w(
      LogSource.ui,
      LogTags.service,
      'CHƯA bật theo dõi liên tục: thiếu quyền vị trí. Foreground service dùng '
      'kiểu "location" nên cần quyền vị trí — hãy cấp quyền rồi mở lại app',
    );
    return false;
  }

  final interval = await BackgroundPrefsStore().intervalMinutes();
  initWeatherForegroundService(intervalMinutes: interval);
  if (await FlutterForegroundTask.isRunningService) {
    if (!allowRestart) return true;
    final res = await FlutterForegroundTask.restartService();
    return _logServiceRequest('restart', res);
  }
  final res = await FlutterForegroundTask.startService(
    serviceId: kForegroundServiceId,
    notificationTitle: 'KatoAssistant đang theo dõi thời tiết',
    notificationText: 'Đang cập nhật tình hình thời tiết…',
    callback: foregroundStartCallback,
  );
  return _logServiceRequest('start', res);
}

/// Quyền vị trí đủ để start FGS kiểu `location` chưa (foreground là đủ; "Luôn
/// cho phép" chỉ cần cho việc XIN FIX MỚI ở nền).
Future<bool> _hasLocationPermissionForFgs() async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    // Không hỏi được quyền → không mạo hiểm start (SecurityException = sập app).
    return false;
  }
}

/// `startService`/`restartService` của plugin KHÔNG ném lỗi — nó trả
/// `ServiceRequestFailure`. Bản cũ bỏ qua giá trị trả về nên một lần bật thất
/// bại hoàn toàn vô hình trong nhật ký.
Future<bool> _logServiceRequest(String what, ServiceRequestResult res) async {
  if (res is ServiceRequestFailure) {
    await AppLog.e(
      LogSource.ui,
      LogTags.service,
      'foreground service $what THẤT BẠI',
      error: res.error,
    );
    await ForegroundServiceHealth.markDead();
    return false;
  }
  await AppLog.i(
      LogSource.ui, LogTags.service, 'foreground service $what thành công');
  await ForegroundServiceHealth.markAlive();
  await ForegroundServiceHealth.clearNudgeNotification();
  return true;
}

/// Tắt service (gỡ thông báo thường trực) theo Ý ĐỊNH của người dùng.
///
/// Xoá luôn mốc "đã chết" + thông báo nhắc: đây là dừng CÓ CHỦ Ý, không phải sự
/// cố — nhắc người dùng bật lại thứ họ vừa tự tắt là sai.
Future<void> stopWeatherForegroundService() async {
  await FlutterForegroundTask.stopService();
  await ForegroundServiceHealth.markAlive();
  await ForegroundServiceHealth.clearNudgeNotification();
}
