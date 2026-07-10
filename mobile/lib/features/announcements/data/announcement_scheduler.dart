import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../core/background/announcement_alarm.dart';
import '../../../core/notifications/notification_service.dart';
import '../../alerts/data/digest_scheduler.dart' show canScheduleExactAlarms;
import 'announcement_prefs_store.dart';

/// Lập lịch (hoặc huỷ) việc kiểm tra tin mới hằng ngày qua alarm hệ thống —
/// theo ĐÚNG mẫu bản tin (digest): `oneShotAt` exact + allowWhileIdle, tự re-arm
/// trong callback. Idempotent → gọi mỗi chu kỳ nền/mở app để tự chữa.
///
/// Dùng `oneShotAt` thay vì `periodic` vì `periodic` (setRepeating) inexact và
/// bị hoãn trong Doze; poll tin mỗi ngày cần nổ đúng mốc.
Future<void> scheduleAnnouncementCheck(AnnouncementPrefs prefs) async {
  await AndroidAlarmManager.cancel(NotificationIds.announcementAlarm);
  if (!prefs.enabled) return;
  await scheduleAnnouncementSlot(
      NotificationIds.announcementAlarm, prefs.checkMinutes);
}

/// Đặt một alarm one-shot cho mốc kế tiếp của [minutesOfDay]. Public để
/// [announcementCheckCallback] gọi lại (re-arm) cho ngày hôm sau.
Future<void> scheduleAnnouncementSlot(int id, int minutesOfDay) async {
  final exact = await canScheduleExactAlarms();
  if (!exact) {
    debugPrint(
      'KatoAssistant: thiếu quyền báo thức chính xác → poll tin dùng alarm '
      'inexact (có thể lệch giờ).',
    );
  }
  await AndroidAlarmManager.oneShotAt(
    _nextInstanceOf(minutesOfDay),
    id,
    announcementCheckCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}

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
