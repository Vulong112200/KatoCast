import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../../../core/background/digest_alarm.dart';
import '../../../core/notifications/notification_service.dart';
import 'notification_prefs_store.dart';

/// Lập lịch (hoặc huỷ) hai bản tin hằng ngày qua alarm hệ thống
/// (android_alarm_manager_plus).
///
/// Gọi mỗi khi: mở app, đổi cài đặt bản tin, hoặc worker nền chạy — để lịch
/// luôn khớp cài đặt hiện tại. Alarm tự bắn đúng mốc giờ kể cả khi app đã tắt;
/// tại thời điểm bắn, [digestAlarmCallback] mới FETCH dữ liệu tươi rồi hiển thị
/// (không bake nội dung sẵn → hết cảnh dữ liệu cũ). Vì thế KHÔNG cần truyền
/// `WeatherData` vào đây nữa.
///
/// - `!prefs.enabled` → huỷ cả hai alarm.
Future<void> scheduleDigests(DigestPrefs prefs) async {
  if (!prefs.enabled) {
    await AndroidAlarmManager.cancel(NotificationIds.dailyDigestMorning);
    await AndroidAlarmManager.cancel(NotificationIds.dailyDigestEvening);
    return;
  }

  await _scheduleSlot(NotificationIds.dailyDigestMorning, prefs.morningMinutes);
  await _scheduleSlot(NotificationIds.dailyDigestEvening, prefs.eveningMinutes);
}

/// Lập một alarm lặp mỗi ngày cho mốc [minutesOfDay] (phút-trong-ngày).
/// `exact + wakeup + allowWhileIdle` để bắn đúng giờ kể cả trong Doze;
/// `rescheduleOnReboot` để lịch sống lại sau khi khởi động lại máy.
Future<void> _scheduleSlot(int id, int minutesOfDay) async {
  await AndroidAlarmManager.periodic(
    const Duration(days: 1),
    id,
    digestAlarmCallback,
    startAt: _nextInstanceOf(minutesOfDay),
    exact: true,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
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
