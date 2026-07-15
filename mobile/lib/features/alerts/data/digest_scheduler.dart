import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/background/digest_alarm.dart';
import '../../../core/config/app_config.dart';
import '../../../core/notifications/notification_service.dart';
import 'notification_prefs_store.dart';

// Trạng thái lập lịch gần nhất (SharedPreferences) — để throttle self-heal và
// biết đã đặt bao nhiêu slot (hủy đúng slot thừa, không quét blanket 64).
const String _kLastScheduleMsKey = 'digest_last_schedule_ms';
const String _kScheduledCountKey = 'digest_scheduled_count';

/// Khoảng throttle self-heal: các lời gọi nền (tick FG mỗi 15') KHÔNG lập lại
/// lịch thường xuyên hơn mức này — vừa tránh ANR (burst binder call) vừa tránh
/// race hủy-rồi-đặt-lại clobber mốc sắp nổ. App mở / đổi cài đặt gọi `force`.
const int _kMinRescheduleGapMs = 60 * 60 * 1000; // 1 giờ

/// Cửa sổ "vừa qua": nếu mốc hôm nay đã qua trong khoảng này, KHÔNG đụng vào
/// alarm của mốc đó (để callback tự re-arm ngày mai) — tránh dời nhầm mốc sáng
/// sang ngày mai khi self-heal chạy sát giờ nổ.
const int _kJustPassedGraceMinutes = 20;

/// Lập lịch (hoặc huỷ) các bản tin hằng ngày qua alarm hệ thống
/// (android_alarm_manager_plus). Danh sách mốc giờ tùy ý → mỗi mốc một alarm ID
/// trong dải động `NotificationIds.digestBase + index`.
///
/// Gọi mỗi khi: mở app, đổi cài đặt bản tin, hoặc worker nền chạy — để lịch
/// luôn khớp cài đặt hiện tại. Alarm tự bắn đúng mốc giờ kể cả khi app đã tắt;
/// tại thời điểm bắn, [digestAlarmCallback] mới FETCH dữ liệu tươi rồi hiển thị.
///
/// Idempotent: luôn hủy TOÀN DẢI trước khi đặt lại → thêm/xóa mốc hay chuỗi
/// one-shot bị đứt (mất quyền exact tạm thời) đều tự chữa mỗi lần gọi.
///
/// LƯU Ý QUAN TRỌNG (fix bản tin không nổ): dùng **oneShotAt** thay vì
/// `periodic`. Plugin hiện thực `periodic` bằng `AlarmManager.setRepeating` —
/// vốn INEXACT và KHÔNG allow-while-idle, nên trong Doze mốc sáng bị hoãn tới
/// cửa sổ bảo trì → "không nổ". Vì one-shot không tự lặp, [digestAlarmCallback]
/// phải tự đặt lại mốc ngày mai (xem `scheduleDigestSlot`).
/// [force] = true khi người dùng chủ động (mở app / đổi cài đặt): bỏ qua
/// throttle để áp lịch mới ngay. Lời gọi nền (tick FG) để mặc định false → chỉ
/// self-heal tối đa 1 lần/giờ, tránh ANR và tránh clobber mốc sắp nổ.
Future<void> scheduleDigests(DigestPrefs prefs, {bool force = false}) async {
  final sp = await SharedPreferences.getInstance();
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (!force) {
    final lastMs = sp.getInt(_kLastScheduleMsKey) ?? 0;
    if (lastMs != 0 && nowMs - lastMs < _kMinRescheduleGapMs) return;
  }

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

  if (prefs.enabled) {
    final now = DateTime.now();
    for (var i = 0; i < prefs.times.length; i++) {
      // Tránh CLOBBER: mốc hôm nay vừa qua trong grace window → để nguyên alarm
      // đang chờ/đã nổ (callback tự re-arm ngày mai) thay vì dời sang mai.
      if (_justPassed(now, prefs.times[i])) continue;
      await scheduleDigestSlot(NotificationIds.digestBase + i, prefs.times[i]);
    }
  }

  await sp.setInt(_kLastScheduleMsKey, nowMs);
  await sp.setInt(_kScheduledCountKey, desired);
}

/// Mốc [minutesOfDay] hôm nay có vừa trôi qua trong [_kJustPassedGraceMinutes]?
bool _justPassed(DateTime now, int minutesOfDay) {
  final target = DateTime(
    now.year,
    now.month,
    now.day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  );
  final diff = now.difference(target).inMinutes;
  return diff >= 0 && diff <= _kJustPassedGraceMinutes;
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
Future<void> scheduleDigestSlot(int id, int minutesOfDay) async {
  final exact = await canScheduleExactAlarms();
  if (!exact) {
    debugPrint(
      'KatoCast: thiếu quyền báo thức chính xác → bản tin dùng alarm inexact '
      '(có thể lệch giờ). Cấp quyền trong app để nổ đúng mốc.',
    );
  }
  await AndroidAlarmManager.oneShotAt(
    _nextInstanceOf(minutesOfDay),
    id,
    digestAlarmCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
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
  await AndroidAlarmManager.oneShotAt(
    DateTime.now().add(delay),
    NotificationIds.digestTest,
    digestAlarmCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
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

/// Mốc kế tiếp của [minutesOfDay] theo giờ địa phương; nếu hôm nay đã qua thì
/// lùi sang ngày mai.
DateTime _nextInstanceOf(int minutesOfDay) {
  final now = DateTime.now();
  var scheduled = DateTime(
    now.year,
    now.month,
    now.day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  );
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}
