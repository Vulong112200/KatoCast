import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/background/digest_alarm.dart';
import '../../../core/config/app_config.dart';
import '../../../core/notifications/notification_service.dart';
import 'notification_prefs_store.dart';

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
Future<void> scheduleDigests(DigestPrefs prefs) async {
  // Hủy mô hình CŨ (2 mốc cố định) một lần — an toàn kể cả khi chưa từng đặt.
  await AndroidAlarmManager.cancel(NotificationIds.dailyDigestMorning);
  await AndroidAlarmManager.cancel(NotificationIds.dailyDigestEvening);

  // Hủy toàn dải động trước khi đặt lại (idempotent + dọn mốc đã xóa).
  for (var i = 0; i < AppConfig.digestMaxSlots; i++) {
    await AndroidAlarmManager.cancel(NotificationIds.digestBase + i);
  }

  if (!prefs.enabled) return;

  for (var i = 0; i < prefs.times.length; i++) {
    await scheduleDigestSlot(NotificationIds.digestBase + i, prefs.times[i]);
  }
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
