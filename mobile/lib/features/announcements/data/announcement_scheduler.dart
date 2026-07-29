import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../../../core/background/alarm_schedule_guard.dart';
import '../../../core/background/announcement_alarm.dart';
import '../../../core/diagnostics/app_log.dart';
import '../../../core/diagnostics/log_entry.dart';
import '../../../core/diagnostics/log_tags.dart';
import '../../../core/notifications/notification_service.dart';
import '../../alerts/data/digest_scheduler.dart' show canScheduleExactAlarms;
import 'announcement_prefs_store.dart';

/// Khoá throttle self-heal cho lịch poll tin.
const String _kLastScheduleMsKey = 'announcement_last_schedule_ms';

/// Lập lịch (hoặc huỷ) việc kiểm tra tin mới hằng ngày qua alarm hệ thống —
/// theo ĐÚNG mẫu bản tin (digest): `oneShotAt` exact + allowWhileIdle, tự re-arm
/// trong callback.
///
/// Dùng `oneShotAt` thay vì `periodic` vì `periodic` (setRepeating) inexact và bị
/// hoãn trong Doze; poll tin mỗi ngày cần nổ đúng mốc.
///
/// QUAN TRỌNG — hai guard giống bản tin (trước đây thiếu, gây báo lại tin):
/// - **throttle**: hàm này được gọi ở MỌI chu kỳ nền; nếu mỗi lần đều
///   `cancel` + đặt lại thì lệnh cancel từ isolate này đua với re-arm từ isolate
///   alarm → lịch bị mất hoặc mốc bị dời sai.
/// - **justPassed**: mốc vừa trôi qua thì để callback tự re-arm cho ngày mai,
///   không dời nhầm sang hôm sau.
///
/// [force] = true khi người dùng chủ động (mở app / đổi cài đặt).
Future<void> scheduleAnnouncementCheck(
  AnnouncementPrefs prefs, {
  bool force = false,
  String source = LogSource.ui,
}) async {
  if (!await AlarmScheduleGuard.claimSchedule(
    _kLastScheduleMsKey,
    force: force,
  )) {
    return;
  }

  if (!prefs.enabled) {
    await AndroidAlarmManager.cancel(NotificationIds.announcementAlarm);
    await AppLog.i(
      source,
      LogTags.announce,
      'theo dõi tin đang TẮT → đã hủy lịch poll',
    );
    return;
  }

  // Mốc vừa trôi qua → alarm của chính nó đang chờ/đã nổ và sẽ tự re-arm; đụng
  // vào lúc này là dời nhầm sang ngày mai.
  if (AlarmScheduleGuard.justPassed(DateTime.now(), prefs.checkMinutes)) {
    await AppLog.i(
      source,
      LogTags.announce,
      'mốc kiểm tra tin vừa trôi qua → để callback tự re-arm',
    );
    return;
  }

  await scheduleAnnouncementSlot(
    NotificationIds.announcementAlarm,
    prefs.checkMinutes,
    source: source,
  );
}

/// Đặt một alarm one-shot cho mốc kế tiếp của [minutesOfDay]. Public để
/// [announcementCheckCallback] gọi lại (re-arm) cho ngày hôm sau.
Future<void> scheduleAnnouncementSlot(
  int id,
  int minutesOfDay, {
  String source = LogSource.announce,
}) async {
  final exact = await canScheduleExactAlarms();
  final fireAt = AlarmScheduleGuard.nextInstanceOf(minutesOfDay);
  await AndroidAlarmManager.oneShotAt(
    fireAt,
    id,
    announcementCheckCallback,
    exact: exact,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
  await AppLog.i(
    source,
    LogTags.arm,
    'đặt lịch poll tin${exact ? '' : ' (INEXACT — thiếu quyền báo thức chính xác)'}',
    data: {
      'id': id,
      'lúc': fireAt.toLocal().toString(),
      'at': fireAt.millisecondsSinceEpoch,
    },
  );
}
