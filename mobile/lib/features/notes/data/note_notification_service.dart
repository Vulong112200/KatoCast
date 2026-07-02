import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/notifications/notification_service.dart';
import '../domain/entities/note.dart';
import 'note_local_datasource.dart';

/// Base ID notification cho ghi chú — cách xa dải weather (1001–1006).
const int kNoteNotifBase = 10000;

/// ActionId của nút "Đã đọc" trên notification ghim/nhắc sticky.
const String kNoteMarkReadActionId = 'note_mark_read';

/// Mỗi note chiếm 16 slot ID liên tiếp, KHÔNG bao giờ đụng nhau giữa các note:
/// - slot 0      = notification GHIM sticky (show trực tiếp, không lập lịch)
/// - slot 1..7   = lịch nhắc lặp TUẦN theo `DateTime.weekday` (1=Thứ 2 … 7=CN)
/// - slot 8      = lịch nhắc MỘT LẦN hoặc HẰNG NGÀY
int noteSlotId(int noteId, int slot) => kNoteNotifBase + noteId * 16 + slot;

/// Toàn bộ 9 slot ID của một note (để cancel sạch).
List<int> allNoteSlotIds(int noteId) =>
    [for (var s = 0; s <= 8; s++) noteSlotId(noteId, s)];

/// Một mốc lập lịch nhắc đã tính sẵn từ cấu hình note.
class NoteReminderSlot {
  /// 1..7 (thứ, lặp tuần) hoặc 8 (một lần / hằng ngày).
  final int slot;

  /// Lần bắn đầu tiên (giờ địa phương, luôn ở tương lai).
  final tz.TZDateTime firstFire;

  /// null = một lần; time = lặp ngày; dayOfWeekAndTime = lặp tuần.
  final DateTimeComponents? match;

  const NoteReminderSlot({
    required this.slot,
    required this.firstFire,
    required this.match,
  });
}

/// Tính các mốc lập lịch từ cấu hình note. Thuần (nhận [now]) để test được.
///
/// - `none`: `remindAt` còn tương lai → 1 slot (8); đã qua → rỗng (không lập
///   lịch quá khứ — zonedSchedule sẽ ném ArgumentError).
/// - `daily`: mốc kế tiếp của giờ:phút (hôm nay hoặc mai) + match `time`.
/// - `weekly`: mỗi thứ trong `weekdaysMask` → 1 slot (1..7) tại mốc kế tiếp
///   của thứ đó + match `dayOfWeekAndTime`; mask rỗng → rỗng.
List<NoteReminderSlot> buildReminderSlots(Note note, tz.TZDateTime now) {
  final at = note.remindAt;
  if (at == null) return const [];

  switch (note.repeat) {
    case NoteRepeat.none:
      final fire = tz.TZDateTime(
          tz.local, at.year, at.month, at.day, at.hour, at.minute);
      if (!fire.isAfter(now)) return const [];
      return [NoteReminderSlot(slot: 8, firstFire: fire, match: null)];

    case NoteRepeat.daily:
      var fire =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, at.hour, at.minute);
      if (!fire.isAfter(now)) fire = fire.add(const Duration(days: 1));
      return [
        NoteReminderSlot(slot: 8, firstFire: fire, match: DateTimeComponents.time),
      ];

    case NoteRepeat.weekly:
      final slots = <NoteReminderSlot>[];
      for (var weekday = 1; weekday <= 7; weekday++) {
        if (note.weekdaysMask & (1 << (weekday - 1)) == 0) continue;
        var fire = tz.TZDateTime(
            tz.local, now.year, now.month, now.day, at.hour, at.minute);
        while (fire.weekday != weekday || !fire.isAfter(now)) {
          fire = fire.add(const Duration(days: 1));
        }
        slots.add(NoteReminderSlot(
          slot: weekday,
          firstFire: fire,
          match: DateTimeComponents.dayOfWeekAndTime,
        ));
      }
      return slots;
  }
}

/// Body notification: nội dung note + checklist mỗi mục một dòng ☑/☐.
String buildPinnedBody(Note note, List<NoteItem> items) {
  final lines = <String>[
    if (note.body.trim().isNotEmpty) note.body.trim(),
    for (final it in items) '${it.done ? '☑' : '☐'} ${it.content}',
  ];
  return lines.join('\n');
}

/// Payload JSON gắn vào notification để handler biết note nào.
String notePayload(int noteId) => jsonEncode({'noteId': noteId});

/// Parse noteId từ payload; null nếu không phải payload của note.
int? parseNotePayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final map = jsonDecode(payload);
    final id = map is Map ? map['noteId'] : null;
    return id is int ? id : null;
  } catch (_) {
    return null;
  }
}

/// Ghim/bỏ ghim + lập/huỷ lịch nhắc cho ghi chú.
///
/// MỌI thay đổi note đều đi qua [sync] (cancel cả 9 slot → dựng lại từ trạng
/// thái hiện tại) để không có bug cập nhật nửa vời (vd sticky bị "bake" vào
/// lịch cũ sau khi bỏ ghim). Class thuần Dart — dùng được ở mọi isolate.
class NoteNotificationService {
  final NotificationService _notif;
  const NoteNotificationService(this._notif);

  /// Đồng bộ TOÀN BỘ notification/lịch của [note] theo trạng thái hiện tại.
  Future<void> sync(Note note, List<NoteItem> items) async {
    final id = note.id;
    if (id == null) return;
    await cancelAll(id);
    if (note.done) return;
    if (note.pinned) await _showPinned(note, items);
    await _scheduleReminders(note, items);
  }

  /// Huỷ cả notification ghim lẫn mọi lịch nhắc của note (9 slot).
  Future<void> cancelAll(int noteId) async {
    for (final id in allNoteSlotIds(noteId)) {
      await _notif.cancel(id);
    }
  }

  /// Chỉ dựng lại các slot LỊCH (1..8), không đụng notification ghim đang
  /// hiển thị — dùng từ background handler sau khi "Đã đọc" (bỏ ghim) để các
  /// lần bắn sau không còn sticky, mà không giết nhầm alarm lặp.
  Future<void> syncReminders(Note note, List<NoteItem> items) async {
    final id = note.id;
    if (id == null) return;
    for (var s = 1; s <= 8; s++) {
      await _notif.cancel(noteSlotId(id, s));
    }
    if (note.done) return;
    await _scheduleReminders(note, items);
  }

  /// Hiện lại notification ghim (không đụng lịch). Dùng khi nội dung checklist
  /// đổi hoặc re-assert sau reboot/"Clear all" — im lặng nhờ channel low +
  /// onlyAlertOnce.
  Future<void> showPinned(Note note, List<NoteItem> items) =>
      _showPinned(note, items);

  Future<void> _showPinned(Note note, List<NoteItem> items) async {
    await _notif.showWithDetails(
      id: noteSlotId(note.id!, 0),
      title: '📌 ${note.title}',
      body: buildPinnedBody(note, items),
      details: _details(note, items, pinnedChannel: true),
      payload: notePayload(note.id!),
    );
  }

  Future<void> _scheduleReminders(Note note, List<NoteItem> items) async {
    final slots = buildReminderSlots(note, tz.TZDateTime.now(tz.local));
    for (final s in slots) {
      try {
        await _notif.zonedScheduleWithDetails(
          id: noteSlotId(note.id!, s.slot),
          title: '⏰ ${note.title}',
          body: buildPinnedBody(note, items),
          when: s.firstFire,
          details: _details(note, items, pinnedChannel: false),
          payload: notePayload(note.id!),
          matchDateTimeComponents: s.match,
        );
      } on PlatformException {
        // Android 12: user có thể thu hồi quyền exact alarm → fallback inexact
        // (bắn xê dịch vài phút nhưng vẫn nhắc được).
        await _notif.zonedScheduleWithDetails(
          id: noteSlotId(note.id!, s.slot),
          title: '⏰ ${note.title}',
          body: buildPinnedBody(note, items),
          when: s.firstFire,
          details: _details(note, items, pinnedChannel: false),
          payload: notePayload(note.id!),
          matchDateTimeComponents: s.match,
          scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  /// Details Android: ghim → channel im lặng; nhắc → channel high.
  /// Note đang ghim ⇒ mọi notification (kể cả bản nhắc) đều sticky
  /// (`ongoing` + không autoCancel) và chỉ gỡ được qua nút "Đã đọc".
  NotificationDetails _details(
    Note note,
    List<NoteItem> items, {
    required bool pinnedChannel,
  }) {
    final sticky = note.pinned;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        pinnedChannel
            ? NotificationService.notePinnedChannelId
            : NotificationService.noteReminderChannelId,
        pinnedChannel ? 'Ghi chú ghim' : 'Nhắc ghi chú',
        channelDescription: pinnedChannel
            ? 'Ghi chú được ghim cố định trên thanh thông báo.'
            : 'Thông báo nhắc ghi chú theo lịch bạn đặt.',
        importance: pinnedChannel ? Importance.low : Importance.high,
        priority: pinnedChannel ? Priority.low : Priority.high,
        ongoing: sticky,
        autoCancel: !sticky,
        onlyAlertOnce: pinnedChannel,
        styleInformation: BigTextStyleInformation(
          buildPinnedBody(note, items),
          contentTitle: pinnedChannel ? '📌 ${note.title}' : '⏰ ${note.title}',
        ),
        actions: sticky
            ? const [
                AndroidNotificationAction(
                  kNoteMarkReadActionId,
                  'Đã đọc ✓',
                  cancelNotification: true,
                  showsUserInterface: false,
                ),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }
}

/// Re-assert sau reboot / "Clear all" (Android 14 cho phép gỡ cả ongoing):
/// hiện lại mọi note ghim còn hoạt động + lập lại lịch nhắc theo DB.
/// Gọi ở: `main._bootstrap()` và chu kỳ WorkManager 15'.
Future<void> reassertNoteNotifications(
  AppDatabase db,
  NotificationService notif,
) async {
  final ds = NoteLocalDataSource(db);
  final svc = NoteNotificationService(notif);
  for (final n in await ds.getPinnedActive()) {
    await svc.showPinned(n, await ds.getItems(n.id!));
  }
  for (final n in await ds.getWithReminders()) {
    await svc.syncReminders(n, await ds.getItems(n.id!));
  }
}
