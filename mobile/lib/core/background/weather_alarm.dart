import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/notes/data/note_notification_service.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../notifications/notification_service.dart';
import 'cycle_lock.dart';
import 'background_prefs.dart';
import 'foreground_service.dart';
import 'weather_check.dart';

/// ID alarm kiểm tra thời tiết (khác các ID bản tin 1005/1006 và ID ghi chú).
const int kWeatherAlarmId = 2001;

/// Khoá SharedPreferences lưu mốc alarm kế tiếp ĐÃ ĐẶT (ms epoch). Dùng để lớp
/// khác (WorkManager) phát hiện chuỗi alarm đã ĐỨT mà dựng lại — thay vì cứ
/// arm lại vô điều kiện và đẩy lùi một alarm đang sắp nổ.
const String kWeatherAlarmNextMsKey = 'weather_alarm_next_ms';

/// Sai số cho phép trước khi coi alarm là "quá hạn không nổ". Alarm exact có thể
/// lệch vài phút trong Doze nên cần biên độ, tránh dựng lại oan.
const Duration kAlarmOverdueGrace = Duration(minutes: 5);

/// Số phút thử lại SỚM khi lần fetch nền vừa rồi thất bại (trả cache cũ) — để
/// buổi sáng bắt được dữ liệu tươi ngay khi radio tỉnh, không phải đợi hết chu
/// kỳ đầy.
const int kFallbackRetryMinutes = 5;

/// Bước nhảy TỐI ĐA của alarm khi đang NGOÀI khung giờ hoạt động.
///
/// Trước đây, ngoài khung thì alarm nhảy một phát tới giờ mở khung (vd 21:05 →
/// 05:00). Nghĩa là suốt 8 tiếng đêm, TOÀN BỘ chuỗi nền treo trên đúng MỘT alarm:
/// mất nó (OEM giết tiến trình, Doze, callback ném lỗi trước bước re-arm) là app
/// đứng im tới khi người dùng mở app hoặc khởi động lại máy — đúng triệu chứng
/// "tối vẫn chạy, sáng ra không thấy gì, restart máy thì lại chạy".
///
/// Nay ban đêm alarm vẫn nhảy từng chặng ~2 tiếng. Mỗi chặng KHÔNG lấy dữ liệu
/// (vẫn mát máy, vẫn tiết kiệm hạn mức API) — chỉ tự kiểm tra và sửa chuỗi:
/// re-arm chính nó, hồi sinh foreground service nếu bị giết, tự chữa lịch bản
/// tin. Mất một chặng thì chỉ mất 2 tiếng thay vì cả đêm.
const Duration kNightHopInterval = Duration(hours: 2);

/// Đặt mốc alarm kế tiếp.
///
/// Trong khung giờ hoạt động → chu kỳ bình thường (`now + interval`).
/// Ngoài khung → chặng đêm (xem [kNightHopInterval]), tối đa là giờ mở khung.
///
/// [retrySoon] = true khi `runWeatherCheck` vừa rồi chỉ có cache cũ (fetch thất
/// bại) → đặt mốc gần hơn ([kFallbackRetryMinutes]) để mau có dữ liệu tươi.
///
/// [firstDelayMinutes] ghi đè khoảng chờ (dùng lúc bật lần đầu để TÁCH PHA khỏi
/// foreground service — xem `applyBackgroundTriggers`).
Future<void> scheduleWeatherAlarm({
  bool retrySoon = false,
  int? firstDelayMinutes,
  String source = LogSource.alarm,
}) async {
  final now = DateTime.now();
  final withinWindow = await isWithinActiveHours(now);
  final DateTime fireAt;
  if (firstDelayMinutes != null) {
    fireAt = now.add(Duration(minutes: firstDelayMinutes));
  } else if (withinWindow) {
    final interval = await BackgroundPrefsStore().intervalMinutes();
    final minutes = retrySoon && interval > kFallbackRetryMinutes
        ? kFallbackRetryMinutes
        : interval;
    fireAt = now.add(Duration(minutes: minutes));
  } else {
    // Chặng đêm: sớm hơn trong hai mốc — giờ mở khung, hoặc chặng ~2 tiếng.
    final windowStart = await nextActiveWindowStart(now);
    final nextHop = now.add(kNightHopInterval);
    fireAt = nextHop.isBefore(windowStart) ? nextHop : windowStart;
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
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kWeatherAlarmNextMsKey, fireAt.millisecondsSinceEpoch);
  } catch (_) {
    // Không ghi được mốc → watchdog WorkManager mất tác dụng, chuỗi vẫn chạy.
  }
  await AppLog.i(
    source,
    LogTags.arm,
    'đặt alarm thời tiết kế tiếp',
    data: {
      'lúc': fireAt.toLocal().toString(),
      'at': fireAt.millisecondsSinceEpoch,
      'sau': '${fireAt.difference(now).inMinutes}p',
      'khung': withinWindow ? 'trong' : 'ngoài (chặng đêm)',
      if (retrySoon) 'lý do': 'thử lại sớm sau khi fetch lỗi',
    },
  );
}

/// Chuỗi alarm có dấu hiệu ĐỨT chưa? True khi mốc đã đặt trôi qua hơn
/// [kAlarmOverdueGrace] mà không có ai re-arm (callback không chạy → tiến trình
/// bị giết hoặc alarm bị hệ thống hủy).
///
/// Dùng bởi WorkManager để chỉ dựng lại chuỗi khi CẦN, thay vì arm lại mỗi lượt
/// (arm lại vô điều kiện sẽ đẩy lùi một alarm đang sắp nổ).
Future<({bool overdue, DateTime? expectedAt})> weatherAlarmChainStatus() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // reload: mốc do isolate alarm ghi, isolate này phải đọc bản mới nhất.
    await prefs.reload();
    final ms = prefs.getInt(kWeatherAlarmNextMsKey);
    if (ms == null) return (overdue: true, expectedAt: null);
    final expected = DateTime.fromMillisecondsSinceEpoch(ms);
    final overdue = DateTime.now().isAfter(expected.add(kAlarmOverdueGrace));
    return (overdue: overdue, expectedAt: expected);
  } catch (_) {
    return (overdue: false, expectedAt: null);
  }
}

/// Huỷ alarm (khi cần).
Future<void> cancelWeatherAlarm() =>
    AndroidAlarmManager.cancel(kWeatherAlarmId);

@pragma('vm:entry-point')
void weatherAlarmCallback() {
  _run();
}

Future<void> _run() async {
  const src = LogSource.alarm;
  await AppLog.i(src, LogTags.cycle, 'alarm nổ — bắt đầu chu kỳ',
      data: {'id': kWeatherAlarmId});

  final withinWindow = await isWithinActiveHours(DateTime.now());
  var retrySoon = false;

  try {
    // Hồi sinh FG service KHÔNG cần DB nên để ngoài lock — đây là việc quan
    // trọng nhất của alarm với vai trò backstop, phải chạy kể cả khi bị bỏ lượt.
    await _reviveForegroundServiceIfNeeded(src);

    if (!withinWindow) {
      // Chặng đêm: KHÔNG lấy dữ liệu, KHÔNG mở DB. Vẫn tự chữa lịch bản tin để
      // mốc sáng (6:30) không bị mất nếu chuỗi digest đứt trong đêm.
      await AppLog.i(
        src,
        LogTags.window,
        'ngoài khung giờ hoạt động → chặng đêm, không lấy dữ liệu',
      );
      try {
        final dp = await NotificationPrefsStore().read();
        await scheduleDigests(dp, source: src);
      } catch (e, st) {
        await AppLog.e(src, LogTags.digest, 'lỗi tự chữa lịch bản tin ban đêm',
            error: e, stack: st);
      }
    } else {
      await AppLog.i(src, LogTags.window, 'trong khung giờ hoạt động → chạy');
      // TOÀN BỘ phần dùng DB nằm TRONG cycle lock — kể cả re-assert ghi chú —
      // để alarm và tick foreground service không bao giờ truy vấn cùng file
      // SQLite một lúc (nguồn của `database is locked` + thông báo trùng).
      final data = await CycleLock.runGuarded(src, () async {
        // Một AppDatabase DUY NHẤT cho cả chu kỳ. Trước đây mỗi phần tự mở một
        // handle → 2 isolate DB mỗi lần chạy, nhân với FG song song là 4.
        final db = AppDatabase();
        try {
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
      retrySoon = data?.fromCacheFallback ?? false;
    }
  } catch (e, st) {
    await AppLog.e(src, LogTags.cycle, 'lỗi trong chu kỳ alarm',
        error: e, stack: st);
  }

  // Re-arm cho chặng kế tiếp (one-shot không tự lặp). LUÔN re-arm, kể cả khi
  // phần trên lỗi — đây là mắt xích giữ cả chuỗi nền sống.
  try {
    await scheduleWeatherAlarm(retrySoon: retrySoon, source: src);
  } catch (e, st) {
    await AppLog.e(
      src,
      LogTags.arm,
      'RE-ARM THẤT BẠI — chuỗi alarm có thể đứt tới khi mở lại app',
      error: e,
      stack: st,
    );
  }
  // Isolate alarm kết thúc ngay sau đây → đẩy hết nhật ký còn trong hàng đợi.
  await AppLog.flush();
}

/// Hồi sinh foreground service nếu người dùng đang bật FG mà service không còn
/// chạy (bị Doze/OEM giết mà tiến trình CHƯA force-stop).
///
/// KHÔNG dùng `restartService()` ở đây: nó reset pha lặp của FG về đúng pha của
/// alarm, khiến hai lớp tick cùng một thời điểm mãi mãi — chính là nguyên nhân
/// tranh chấp DB và thông báo trùng. Chỉ start khi service THẬT SỰ đã chết.
Future<void> _reviveForegroundServiceIfNeeded(String src) async {
  try {
    if (!await BackgroundPrefsStore().foregroundEnabled()) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await startWeatherForegroundService(allowRestart: false);
    await AppLog.w(
      src,
      LogTags.service,
      'foreground service đã chết → alarm hồi sinh lại',
    );
  } catch (e, st) {
    await AppLog.e(src, LogTags.service, 'không hồi sinh được foreground service',
        error: e, stack: st);
  }
}
