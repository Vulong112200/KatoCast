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
import '../notifications/timezone_init.dart';
import 'cycle_lock.dart';
import 'background_prefs.dart';
import 'service_health.dart';
import 'weather_check.dart';

/// ID alarm kiểm tra thời tiết (khác các ID bản tin 1005/1006 và ID ghi chú).
const int kWeatherAlarmId = 2001;

/// Giá trị khoá `loại` trong nhật ký của dòng "đặt alarm thời tiết kế tiếp".
/// `LogHealth` lọc theo nhãn này để lấy đúng mốc alarm THỜI TIẾT kế tiếp, bất kể
/// lớp nào đã đặt (alarm tự re-arm, WorkManager dựng lại, hay mở app).
const String kWeatherAlarmKind = LogTags.armKindWeather;

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
/// re-arm chính nó, ghi nhận tình trạng foreground service, tự chữa lịch bản
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
      // `loại`: nhãn ỔN ĐỊNH để `LogHealth` nhận ra đây là alarm THỜI TIẾT (chứ
      // không phải bản tin/poll tin) mà KHÔNG cần đoán qua `source`. Trước đây
      // LogHealth chỉ nhận dòng có `source == alarm`, nên khi mốc mới nhất do
      // lớp khác đặt (mở app / WorkManager dựng lại) thì nó bỏ qua và lấy dòng
      // CŨ hơn — thẻ Tình trạng hiện "Alarm kế tiếp 14:43 — ĐÃ QUÁ HẠN 45h50"
      // ngay sau khi app vừa đặt mốc mới cách đó 1 giây.
      LogTags.armKindKey: kWeatherAlarmKind,
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

  // Isolate alarm không chạy `main()` → tự khởi tạo múi giờ, nếu không
  // `reassertNoteNotifications` bên dưới nổ `LateInitializationError` trên
  // `tz.local` ở mọi chu kỳ (xem `timezone_init.dart`).
  await ensureTimezoneInitialized();

  final withinWindow = await isWithinActiveHours(DateTime.now());

  // ⚠️ RE-ARM NGAY, TRƯỚC MỌI VIỆC KHÁC — đây là mắt xích giữ cả hệ thống nền
  // sống.
  //
  // Trước đây re-arm nằm ở CUỐI hàm. Nhật ký thật cho thấy hậu quả: 28/07
  // 06:34:03 ghi "alarm nổ" rồi tiến trình chết ngay sau đó — không có cả dòng
  // kiểm tra khung giờ — nên không kịp re-arm và **chuỗi đứt 7 giờ 18 phút**
  // (đúng khoảng "sáng ra app không lấy dữ liệu"). Cùng kiểu, 29/07 mốc 02:14
  // không bao giờ nổ và WorkManager phải dựng lại lúc 07:50.
  //
  // Đặt lịch trước biến chuỗi thành TỰ DUY TRÌ: dù phần dưới có bị OEM giết
  // giữa đường thì mốc kế tiếp đã nằm trong AlarmManager của hệ thống. Đánh đổi
  // duy nhất là mốc chưa biết `retrySoon`; bù lại bằng việc arm lại sớm hơn ở
  // cuối chu kỳ khi fetch thất bại (xem dưới).
  try {
    await scheduleWeatherAlarm(source: src);
  } catch (e, st) {
    await AppLog.e(
      src,
      LogTags.arm,
      'RE-ARM THẤT BẠI — chuỗi alarm có thể đứt tới khi WorkManager dựng lại',
      error: e,
      stack: st,
    );
  }

  var retrySoon = false;
  try {
    // Ghi nhận FG service còn sống hay đã chết (KHÔNG start lại — xem hàm dưới).
    await _reportForegroundServiceState(src);

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

  // Fetch nền thất bại (chỉ có cache cũ) → RÚT NGẮN mốc đã arm ở đầu chu kỳ để
  // mau có dữ liệu tươi khi radio tỉnh. Chỉ ghi đè khi thật sự cần, nên đường
  // bình thường vẫn giữ đúng mốc đã đặt từ đầu.
  if (retrySoon) {
    try {
      await scheduleWeatherAlarm(retrySoon: true, source: src);
    } catch (e, st) {
      await AppLog.e(src, LogTags.arm, 'rút ngắn mốc thử lại THẤT BẠI',
          error: e, stack: st);
    }
  }
  // Isolate alarm kết thúc ngay sau đây → đẩy hết nhật ký còn trong hàng đợi.
  await AppLog.flush();
}

/// GHI NHẬN trạng thái foreground service. **KHÔNG start lại.**
///
/// ⚠️ Bản trước của hàm này là NGUYÊN NHÂN GỐC của lỗi nặng nhất trong app: nó
/// gọi `startWeatherForegroundService()` từ isolate alarm khi thấy service đã
/// chết. Từ Android 12 (API 31), start FGS khi app ở nền bị hệ thống từ chối —
/// và `flutter_foreground_task` gọi `startForeground()` trong `onStartCommand`
/// KHÔNG có try/catch, nên `ForegroundServiceStartNotAllowedException` bay lên
/// luồng chính và **giết cả tiến trình**. Vì lỗi xảy ra ở tầng Java/Service,
/// `try/catch` ở Dart KHÔNG bắt được — bản cũ có catch nhưng vô dụng.
///
/// Nhật ký thật 02/08/2026 là bằng chứng: 12:58, 13:13, 13:28, 13:43, 14:13,
/// 14:28 — mỗi mốc ghi "thử hồi sinh" rồi im lặng tuyệt đối (không có cả dòng
/// thành công lẫn dòng lỗi), tức tiến trình sập ngay tại đó. Sau lần thứ sáu,
/// hệ thống force-stop app → hủy SẠCH alarm one-shot **và** job WorkManager →
/// app đứng im **46 tiếng** tới khi người dùng mở app (`chiếm lại lock quá hạn ·
/// đã: 2765m`). Đây chính là "dùng càng lâu, càng không restart máy thì càng
/// lỗi": một lần FG service chết là app tự sập mỗi 15 phút cho tới khi bị khai
/// tử hoàn toàn.
///
/// Đường hồi phục ĐÚNG (xem [ForegroundServiceHealth]):
/// 1. khi app hiển thị với người dùng → `applyBackgroundTriggers` bật lại (hợp
///    pháp vì lúc đó app ở foreground);
/// 2. `RestartReceiver` của plugin (dùng `setAlarmClock`, được hệ thống miễn
///    trừ) tự start lại khi service bị giết mà tiến trình còn sống;
/// 3. im lặng quá lâu → một thông báo nhắc mở app.
/// Trong lúc đó alarm exact + WorkManager vẫn cập nhật đầy đủ, chỉ trễ hơn.
Future<void> _reportForegroundServiceState(String src) async {
  try {
    if (!await BackgroundPrefsStore().foregroundEnabled()) {
      await AppLog.i(src, LogTags.service,
          'người dùng đã TẮT theo dõi liên tục → không theo dõi tình trạng');
      return;
    }
    final running = await FlutterForegroundTask.isRunningService;
    await ForegroundServiceHealth.reportFromBackground(src, running: running);
  } catch (e, st) {
    await AppLog.e(src, LogTags.service,
        'không đọc được tình trạng foreground service',
        error: e, stack: st);
  }
}
