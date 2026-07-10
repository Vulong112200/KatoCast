import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/notes/data/note_local_datasource.dart';
import '../../features/notes/data/note_notification_service.dart';
import '../app_router.dart';
import '../database/app_database.dart';
import 'notification_service.dart';

/// Chạy ở MAIN isolate khi user chạm vào THÂN notification (app đang chạy /
/// background). Payload của ghi chú → mở màn Ghi chú.
void onNotificationTap(NotificationResponse resp) {
  final payload = resp.payload;
  if (payload != null && payload.startsWith('announcement:')) {
    appRouter.push('/announcements');
    return;
  }
  final noteId = parseNotePayload(payload);
  if (noteId != null) {
    appRouter.push('/notes');
  }
}

/// Chạy ở BACKGROUND isolate riêng khi user bấm nút action "Đã đọc"
/// (`showsUserInterface: false` — không mở app). PHẢI là hàm top-level +
/// entry-point. Cần `ActionBroadcastReceiver` trong AndroidManifest.
///
/// Hành vi (user đã chọn): CHỈ gỡ ghim khỏi khay — note giữ nguyên trong app.
/// - Entry trên khay của notification vừa bấm đã bị gỡ ở tầng native
///   (`cancelNotification: true`).
/// - KHÔNG `cancel()` các slot lịch (1..8) tuỳ tiện — `plugin.cancel` từ Dart
///   giết luôn alarm lặp ngày/tuần; thay vào đó re-sync để các lần bắn sau
///   không còn sticky.
@pragma('vm:entry-point')
Future<void> onNotificationActionBackground(NotificationResponse resp) async {
  if (resp.actionId != kNoteMarkReadActionId) return;
  final noteId = parseNotePayload(resp.payload);
  if (noteId == null) return;

  try {
    // Isolate này không chạy main() → tự init binding (plugin channel) +
    // timezone (thiếu tz.local sẽ là UTC → zonedSchedule re-sync bắn sai giờ).
    WidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {}

    final db = AppDatabase();
    try {
      final ds = NoteLocalDataSource(db);
      await ds.setPinned(noteId, false);

      final notif = NotificationService();
      // Gỡ notification GHIM (slot 0 — luôn là show(), không phải lịch).
      await notif.cancel(noteSlotId(noteId, 0));

      // Re-sync lịch nhắc với trạng thái đã bỏ ghim → lần bắn sau hết sticky.
      final note = await ds.getNote(noteId);
      if (note != null && !note.done) {
        await NoteNotificationService(notif)
            .syncReminders(note, await ds.getItems(noteId));
      }
    } finally {
      await db.close();
    }
  } catch (_) {
    // Nuốt lỗi: isolate action không có UI để báo; lần re-assert kế tiếp
    // (bootstrap/worker) sẽ đưa hệ thống về trạng thái nhất quán.
  }
}
