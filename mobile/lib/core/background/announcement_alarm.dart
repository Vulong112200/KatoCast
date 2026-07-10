import 'package:flutter/foundation.dart';

import '../../features/announcements/data/announcement_prefs_store.dart';
import '../../features/announcements/data/announcement_remote_data_source.dart';
import '../../features/announcements/data/announcement_repository.dart';
import '../../features/announcements/data/announcement_scheduler.dart';
import '../../features/announcements/domain/entities/announcement.dart';
import '../database/app_database.dart';
import '../kato/kato_voice.dart';
import '../notifications/notification_service.dart';

/// Entry-point AndroidAlarmManager gọi ĐÚNG mốc giờ kiểm tra tin (kể cả khi app
/// đã tắt). Chạy trong isolate riêng → tự dựng dependency, KHÔNG dùng Riverpod.
///
/// Vì lịch dùng `oneShotAt` (không tự lặp — cần để nổ đúng giờ trong Doze),
/// callback PHẢI tự đặt lại mốc cho ngày mai ở `finally` (trừ khi đã tắt).
@pragma('vm:entry-point')
void announcementCheckCallback(int id) {
  _runCheck(id);
}

Future<void> _runCheck(int id) async {
  AnnouncementPrefs? prefs;
  try {
    prefs = await AnnouncementPrefsStore().read();
    if (!prefs.enabled) return;
    await _fetchAndNotify(prefs);
  } catch (_) {
    // Nuốt lỗi để alarm không kẹt; mốc kế tiếp (ngày mai) sẽ thử lại.
  } finally {
    try {
      final p = prefs ?? await AnnouncementPrefsStore().read();
      if (p.enabled) {
        await scheduleAnnouncementSlot(id, p.checkMinutes);
      }
    } catch (e) {
      debugPrint('KatoAssistant: re-arm poll tin (id=$id) lỗi: $e');
    }
  }
}

/// Chạy kiểm tra tin NGAY, KHÔNG re-arm alarm — cho nút "Kiểm tra tin mới ngay"
/// (tự chẩn đoán end-to-end). Trả số tin mới đã hiển thị.
Future<int> checkAnnouncementsNow() async {
  final prefs = await AnnouncementPrefsStore().read();
  if (!prefs.enabled) return 0;
  return _fetchAndNotify(prefs);
}

/// Fetch tin chưa thấy → hiển thị thông báo giọng Kato → markSeen. Trả số tin
/// đã hiển thị thành công. Tự dựng + đóng DB (dùng được ở isolate nền lẫn main).
Future<int> _fetchAndNotify(AnnouncementPrefs prefs) async {
  final db = AppDatabase();
  try {
    final repo = AnnouncementRepository(AnnouncementRemoteDataSource(), db);
    final fresh = await repo.fetchNewUnseen(prefs.topics);
    if (fresh.isEmpty) return 0;

    final notif = NotificationService();
    await notif.init();
    final shown = <Announcement>[];
    for (final a in fresh) {
      try {
        await notif.showAnnouncement(
          id: NotificationIds.announcementBase +
              (a.id % NotificationIds.announcementIdSpan),
          title: _title(a),
          body: KatoVoice.announcement(a.firstSeenAt.minute) + _body(a),
          payload: 'announcement:${a.id}',
        );
        shown.add(a);
      } catch (_) {
        // Tin này hiển thị lỗi → KHÔNG markSeen để lần sau thử lại.
      }
    }
    if (shown.isNotEmpty) await repo.markSeen(shown);
    return shown.length;
  } finally {
    await db.close();
  }
}

String _title(Announcement a) {
  final tag = switch (a.topic) {
    'jlpt' => '📣 JLPT',
    'mba' => '🎓 MBA',
    _ => '📣 Tin mới',
  };
  return tag;
}

String _body(Announcement a) {
  final summary = a.summary.isNotEmpty ? a.summary : a.title;
  return '$summary\nNguồn: ${a.sourceDomain}';
}
