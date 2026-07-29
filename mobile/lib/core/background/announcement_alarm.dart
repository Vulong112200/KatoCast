import 'package:shared_preferences/shared_preferences.dart';

import '../../features/announcements/data/announcement_prefs_store.dart';
import '../../features/announcements/data/announcement_remote_data_source.dart';
import '../../features/announcements/data/announcement_repository.dart';
import '../../features/announcements/data/announcement_scheduler.dart';
import '../../features/announcements/domain/entities/announcement.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../kato/kato_voice.dart';
import '../notifications/notification_service.dart';
import 'cycle_lock.dart';

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
  const src = LogSource.announce;
  await AppLog.i(src, LogTags.cycle, 'alarm poll tin nổ', data: {'id': id});

  AnnouncementPrefs? prefs;
  try {
    prefs = await AnnouncementPrefsStore().read();
    if (!prefs.enabled) {
      await AppLog.i(src, LogTags.announce, 'theo dõi tin đang TẮT → bỏ lượt');
      return;
    }
    // Cycle lock: lượt poll cũng ghi Drift (bảng đã-thấy) nên phải xếp hàng với
    // chu kỳ thời tiết, tránh `database is locked`.
    await CycleLock.runGuarded(src, () => _fetchAndNotify(prefs!, src));
  } catch (e, st) {
    await AppLog.e(src, LogTags.announce, 'lỗi khi kiểm tra tin mới',
        error: e, stack: st);
  } finally {
    try {
      final p = prefs ?? await AnnouncementPrefsStore().read();
      if (p.enabled) {
        await scheduleAnnouncementSlot(id, p.checkMinutes, source: src);
      }
    } catch (e, st) {
      await AppLog.e(
        src,
        LogTags.arm,
        'RE-ARM poll tin THẤT BẠI — có thể mất lượt tới khi mở lại app',
        error: e,
        stack: st,
        data: {'id': id},
      );
    }
    await AppLog.flush();
  }
}

/// Chạy kiểm tra tin NGAY, KHÔNG re-arm alarm — cho nút "Kiểm tra tin mới ngay"
/// (tự chẩn đoán end-to-end). Trả số tin mới đã hiển thị.
Future<int> checkAnnouncementsNow() async {
  final prefs = await AnnouncementPrefsStore().read();
  if (!prefs.enabled) return 0;
  // Vẫn qua cycle lock để không đua với lượt poll nền; bị bỏ lượt → trả 0.
  return await CycleLock.runGuarded(
        LogSource.ui,
        () => _fetchAndNotify(prefs, LogSource.ui),
      ) ??
      0;
}

/// Fetch tin chưa thấy → đánh dấu đã-thấy → hiển thị thông báo giọng Kato. Trả số
/// tin đã hiển thị thành công. Tự dựng + đóng DB (dùng được ở isolate nền lẫn main).
///
/// THỨ TỰ QUAN TRỌNG: `markSeen` chạy TRƯỚC `show`. Trước đây show trước rồi mới
/// markSeen — nếu lượt ghi DB thất bại (đang bị isolate khác khoá) thì tin đã hiện
/// mà không được ghi nhận, nên lượt poll sau BÁO LẠI cùng một tin. Nay nếu show
/// lỗi thì [AnnouncementRepository.unmarkSeen] bù trừ để thử lại lần sau.
Future<int> _fetchAndNotify(AnnouncementPrefs prefs, String src) async {
  final db = AppDatabase();
  try {
    final repo = AnnouncementRepository(AnnouncementRemoteDataSource(), db);
    final fresh = await repo.fetchNewUnseen(prefs.topics);
    if (fresh.isEmpty) {
      await AppLog.i(
        src,
        LogTags.announce,
        'không có tin mới',
        data: {'chủ đề': prefs.topics.join(',')},
      );
      return 0;
    }
    await AppLog.i(
      src,
      LogTags.announce,
      'có ${fresh.length} tin mới cần báo',
      data: {'chủ đề': prefs.topics.join(',')},
    );

    // Ghi nhận đã-thấy TRƯỚC (một lượt ghi cho cả lô).
    await repo.markSeen(fresh);

    final failed = <Announcement>[];
    var shown = 0;
    for (final a in fresh) {
      final notifId = await _nextAnnouncementNotificationId();
      try {
        await NotificationService().showAnnouncement(
          id: notifId,
          title: _title(a),
          body: KatoVoice.announcement(a.firstSeenAt.minute) + _body(a),
          payload: 'announcement:${a.id}',
        );
        shown++;
        await AppLog.i(
          src,
          LogTags.notify,
          'ĐÃ BÁO TIN: ${a.title}',
          data: {
            'chủ đề': a.topic,
            'nguồn': a.sourceDomain,
            'id': notifId,
          },
        );
      } catch (e, st) {
        failed.add(a);
        await AppLog.e(src, LogTags.notify, 'không hiển thị được tin: ${a.title}',
            error: e, stack: st);
      }
    }

    // Bù trừ các tin hiển thị lỗi → lượt sau thử lại.
    if (failed.isNotEmpty) {
      try {
        await repo.unmarkSeen(failed);
      } catch (e, st) {
        await AppLog.e(src, LogTags.db, 'không bù trừ được đánh dấu đã-thấy',
            error: e, stack: st);
      }
    }
    return shown;
  } finally {
    try {
      await db.close();
    } catch (e, st) {
      await AppLog.e(src, LogTags.db, 'lỗi đóng DB', error: e, stack: st);
    }
  }
}

/// Khoá SharedPreferences cho bộ đếm slot ID thông báo tin.
const String _kAnnouncementIdCursorKey = 'announcement_notif_id_cursor';

/// ID thông báo kế tiếp trong dải `announcementBase..+span`, cấp theo BỘ ĐẾM
/// XOAY VÒNG.
///
/// Trước đây ID = `base + (remoteId % span)`: hai tin có remote id lệch đúng
/// `span` (500) sẽ trùng ID và tin sau ĐÈ MẤT tin trước trên khay — kể cả khi
/// hiện cùng một lượt. Bộ đếm xoay vòng bảo đảm các tin hiển thị liền nhau luôn
/// khác ID; chỉ sau `span` tin mới quay lại đầu dải.
Future<int> _nextAnnouncementNotificationId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final next = ((prefs.getInt(_kAnnouncementIdCursorKey) ?? 0) + 1) %
        NotificationIds.announcementIdSpan;
    await prefs.setInt(_kAnnouncementIdCursorKey, next);
    return NotificationIds.announcementBase + next;
  } catch (_) {
    // Không đọc được bộ đếm → dùng phút hiện tại làm slot (vẫn khác nhau giữa
    // các lượt poll, đủ tốt cho đường dự phòng).
    return NotificationIds.announcementBase +
        (DateTime.now().minute % NotificationIds.announcementIdSpan);
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
