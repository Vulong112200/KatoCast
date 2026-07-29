import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import 'background_prefs.dart';
import 'background_worker.dart';
import 'foreground_service.dart';
import 'weather_alarm.dart';

/// Điều phối các lớp chạy nền.
///
/// Cả ba lớp (foreground service, alarm exact, WorkManager) đều đổ về
/// `runWeatherCheck`, và `CycleLock` đảm bảo **chỉ một chu kỳ thực sự chạy tại
/// một thời điểm**. Nhờ có lock, nhiều lớp cùng bật là chuyện tốt — mỗi lớp là
/// một đường hồi phục độc lập — thay vì nguồn tranh chấp như trước.
///
/// Quy tắc:
/// - **Foreground service BẬT** (mặc định): FG là lớp CHÍNH (cập nhật liên tục
///   kể cả Doze nhờ wakelock) + alarm exact BACKSTOP + **WorkManager vẫn bật**.
///   Trước đây WorkManager bị hủy khi FG bật; nhưng WorkManager là lớp duy nhất
///   có lịch do **hệ điều hành** giữ (JobScheduler), nên nó sống sót được cả khi
///   chuỗi alarm one-shot của mình bị đứt. Giữ nó lại chính là để cứu ca "sáng ra
///   app đứng im". Chi phí gần như bằng 0: guard quota + cycle lock khiến lượt
///   trùng không gọi API và không chạy chồng.
/// - **Foreground service TẮT**: alarm exact + WorkManager, dừng FG service.
///
/// TÁCH PHA: khi bật cả FG và alarm, alarm được đặt lệch **nửa chu kỳ** so với
/// tick FG. Trước đây hai lớp được arm liền nhau nên tick cùng thời điểm mãi mãi
/// → cùng đọc `AlertStateStore` trước khi bên nào kịp ghi (thông báo trùng) và
/// cùng ghi DB (`database is locked`). Lệch pha biến alarm thành backstop đúng
/// nghĩa: nó chỉ thực sự làm việc khi FG đã chết.
///
/// LƯU Ý: trên OEM diệt tiến trình mạnh (Nubia/MyOS, Xiaomi/HyperOS…), khi người
/// dùng VUỐT TẮT app, OS force-stop → hủy sạch mọi alarm; không cơ chế nào cứu
/// được ngoài việc bật "Tự khởi động" + "Không giới hạn pin" (xem onboarding
/// trong `main.dart`).
///
/// Gọi ở bootstrap và mỗi khi người dùng đổi cài đặt nền. Idempotent + bọc try để
/// một plugin lỗi trên máy nào đó không làm hỏng các lớp còn lại.
Future<void> applyBackgroundTriggers() async {
  const src = LogSource.ui;
  final prefs = BackgroundPrefsStore();
  final foregroundOn = await prefs.foregroundEnabled();
  final interval = await prefs.intervalMinutes();

  await AppLog.i(
    src,
    LogTags.boot,
    'áp cấu hình chạy nền',
    data: {
      'foreground': foregroundOn ? 'bật' : 'tắt',
      'chu kỳ': '${interval}p',
    },
  );

  if (foregroundOn) {
    try {
      await startWeatherForegroundService();
    } catch (e, st) {
      await AppLog.e(src, LogTags.service, 'không bật được foreground service',
          error: e, stack: st);
    }
  } else {
    try {
      await stopWeatherForegroundService();
    } catch (e, st) {
      await AppLog.e(src, LogTags.service, 'không tắt được foreground service',
          error: e, stack: st);
    }
  }

  // WorkManager: lớp có lịch do HĐH giữ → luôn bật, bất kể FG bật hay tắt.
  try {
    await BackgroundScheduler.initialize();
  } catch (e, st) {
    await AppLog.e(src, LogTags.boot, 'không đăng ký được WorkManager',
        error: e, stack: st);
  }

  // Alarm exact: lệch nửa chu kỳ khi FG đang bật để làm backstop đúng nghĩa.
  try {
    await scheduleWeatherAlarm(
      firstDelayMinutes: foregroundOn ? _halfInterval(interval) : null,
      source: src,
    );
  } catch (e, st) {
    await AppLog.e(src, LogTags.arm, 'không đặt được alarm thời tiết',
        error: e, stack: st);
  }
}

/// Nửa chu kỳ, tối thiểu 1 phút (chu kỳ ngắn nhất là 5' → 2').
int _halfInterval(int intervalMinutes) {
  final half = intervalMinutes ~/ 2;
  return half < 1 ? 1 : half;
}
