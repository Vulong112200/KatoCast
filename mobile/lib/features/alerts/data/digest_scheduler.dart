import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/background/alarm_schedule_guard.dart';
import '../../../core/background/digest_alarm.dart';
import '../../../core/config/app_config.dart';
import '../../../core/diagnostics/app_log.dart';
import '../../../core/diagnostics/log_entry.dart';
import '../../../core/diagnostics/log_tags.dart';
import '../../../core/notifications/notification_service.dart';
import 'notification_prefs_store.dart';

// Trạng thái lập lịch gần nhất (SharedPreferences) — để throttle self-heal và
// biết đã đặt bao nhiêu slot (hủy đúng slot thừa, không quét blanket 64).
const String _kLastScheduleMsKey = 'digest_last_schedule_ms';
const String _kScheduledCountKey = 'digest_scheduled_count';

/// Lập lịch (hoặc huỷ) các bản tin hằng ngày qua alarm hệ thống
/// (android_alarm_manager_plus). Danh sách mốc giờ tùy ý → mỗi mốc một alarm ID
/// trong dải động `NotificationIds.digestBase + index`.
///
/// Gọi mỗi khi: mở app, đổi cài đặt bản tin, hoặc chu kỳ nền chạy — để lịch luôn
/// khớp cài đặt hiện tại. Alarm tự bắn đúng mốc giờ kể cả khi app đã tắt; tại
/// thời điểm bắn, [digestAlarmCallback] mới FETCH dữ liệu tươi rồi hiển thị.
///
/// LƯU Ý QUAN TRỌNG (fix bản tin không nổ): dùng **oneShotAt** thay vì
/// `periodic`. Plugin hiện thực `periodic` bằng `AlarmManager.setRepeating` —
/// vốn INEXACT và KHÔNG allow-while-idle, nên trong Doze mốc sáng bị hoãn tới
/// cửa sổ bảo trì → "không nổ". Vì one-shot không tự lặp, [digestAlarmCallback]
/// phải tự đặt lại mốc ngày mai (xem [scheduleDigestSlot]).
///
/// [force] = true khi người dùng chủ động (mở app / đổi cài đặt): bỏ qua throttle
/// để áp lịch mới ngay. Lời gọi nền để mặc định false → chỉ self-heal tối đa 1
/// lần/giờ, tránh ANR và tránh clobber mốc sắp nổ.
Future<void> scheduleDigests(
  DigestPrefs prefs, {
  bool force = false,
  String source = LogSource.ui,
}) async {
  if (!await AlarmScheduleGuard.claimSchedule(
    _kLastScheduleMsKey,
    force: force,
  )) {
    return;
  }

  final sp = await SharedPreferences.getInstance();

  // Hủy mô hình CŨ (2 mốc cố định) một lần — an toàn kể cả khi chưa từng đặt.
  await AndroidAlarmManager.cancel(NotificationIds.dailyDigestMorning);
  await AndroidAlarmManager.cancel(NotificationIds.dailyDigestEvening);

  final desired = prefs.enabled ? prefs.times.length : 0;
  // Số slot đã đặt lần trước: lần ĐẦU (chưa có key) quét toàn dải một lần để dọn
  // alarm cũ từ phiên bản trước; các lần sau chỉ hủy tới max(prev, desired) —
  // KHÔNG blanket 64 mỗi lần (nguồn ANR).
  final prevCount = sp.getInt(_kScheduledCountKey) ?? AppConfig.digestMaxSlots;
  final cancelUpTo = prevCount > desired ? prevCount : desired;
  for (var i = desired; i < cancelUpTo && i < AppConfig.digestMaxSlots; i++) {
    await AndroidAlarmManager.cancel(NotificationIds.digestBase + i);
  }

  if (!prefs.enabled) {
    await AppLog.i(source, LogTags.digest, 'bản tin đang TẮT → đã hủy hết mốc');
    await sp.setInt(_kScheduledCountKey, 0);
    return;
  }

  final now = DateTime.now();
  var armed = 0, skipped = 0;
  for (var i = 0; i < prefs.times.length; i++) {
    // Tránh CLOBBER: mốc hôm nay vừa qua trong grace window → để nguyên alarm
    // đang chờ/đã nổ (callback tự re-arm ngày mai) thay vì dời sang mai.
    if (AlarmScheduleGuard.justPassed(now, prefs.times[i])) {
      skipped++;
      continue;
    }
    await scheduleDigestSlot(
      NotificationIds.digestBase + i,
      prefs.times[i],
      source: source,
    );
    armed++;
  }
  await sp.setInt(_kScheduledCountKey, desired);
  await AppLog.i(
    source,
    LogTags.digest,
    'đã áp lịch bản tin',
    data: {
      'số mốc': prefs.times.length,
      'đã đặt': armed,
      if (skipped > 0) 'bỏ (vừa qua)': skipped,
    },
  );
}

/// Đặt một alarm one-shot cho mốc kế tiếp của [minutesOfDay].
///
/// Ưu tiên `exact + wakeup + allowWhileIdle` để bắn đúng giờ kể cả trong Doze.
/// NHƯNG nếu quyền báo thức chính xác bị thu hồi (Android 12), `exact:true` sẽ
/// ném `SecurityException` khiến bản tin IM LẶNG không nổ. Vì vậy khi không có
/// quyền, ta fallback `exact:false` (inexact + allowWhileIdle) để vẫn nổ gần
/// đúng giờ thay vì mất hẳn. `rescheduleOnReboot` để lịch sống lại sau reboot.
///
/// Public để [digestAlarmCallback] gọi lại (re-arm) cho ngày hôm sau.
Future<void> scheduleDigestSlot(
  int id,
  int minutesOfDay, {
  String source = LogSource.digest,
}) async {
  final exact = await canScheduleExactAlarms();
  final fireAt = AlarmScheduleGuard.nextInstanceOf(minutesOfDay);
  await AndroidAlarmManager.oneShotAt(
    fireAt,
    id,
    digestAlarmCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
  await AppLog.i(
    source,
    LogTags.arm,
    'đặt bản tin${exact ? '' : ' (INEXACT — thiếu quyền báo thức chính xác)'}',
    data: {
      'id': id,
      'lúc': fireAt.toLocal().toString(),
      'at': fireAt.millisecondsSinceEpoch,
    },
  );
}

/// Đặt một bản tin THỬ sau [delay] (mặc định 1 phút) qua alarm hệ thống — công
/// cụ tự chẩn đoán: nếu nó nổ (khi khóa màn hình, KHÔNG vuốt tắt) thì khâu lập
/// lịch OK; nếu vuốt tắt app rồi không nổ → thiết bị force-stop, cần bật Tự khởi
/// động. Dùng `NotificationIds.digestTest` (dưới digestBase) nên callback không
/// re-arm — bắn đúng một lần.
Future<void> scheduleDigestTest({
  Duration delay = const Duration(minutes: 1),
}) async {
  final exact = await canScheduleExactAlarms();
  final fireAt = DateTime.now().add(delay);
  await AndroidAlarmManager.oneShotAt(
    fireAt,
    NotificationIds.digestTest,
    digestAlarmCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
  );
  await AppLog.i(
    LogSource.ui,
    LogTags.arm,
    'đặt BẢN TIN THỬ (tự chẩn đoán)',
    data: {'lúc': fireAt.toLocal().toString(), 'exact': exact},
  );
}

/// Thiết bị hiện có được đặt báo thức CHÍNH XÁC không (Android 12+ mới cần).
/// Trả true khi được cấp hoặc khi nền tảng không áp dụng khái niệm này.
Future<bool> canScheduleExactAlarms() async {
  try {
    return await ph.Permission.scheduleExactAlarm.isGranted;
  } catch (_) {
    // Nền tảng cũ / không hỗ trợ khái niệm exact-alarm → coi như được phép.
    return true;
  }
}
