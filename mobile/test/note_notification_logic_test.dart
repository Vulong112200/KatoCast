import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/notes/data/note_notification_service.dart';
import 'package:katocast/features/notes/domain/entities/note.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Note _note({
  int id = 1,
  DateTime? remindAt,
  NoteRepeat repeat = NoteRepeat.none,
  int weekdaysMask = 0,
  String body = '',
}) {
  final now = DateTime(2026, 7, 2, 10);
  return Note(
    id: id,
    title: 'Test',
    body: body,
    remindAt: remindAt,
    repeat: repeat,
    weekdaysMask: weekdaysMask,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // Init NGAY tại đây (không dùng setUpAll): thân group() chạy lúc KHAI BÁO
  // test — trước setUpAll — mà `tz.local` được dùng để dựng mốc `now`.
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

  group('noteSlotId', () {
    test('unique trên (noteId 1..100) × (slot 0..8) và không đụng dải weather',
        () {
      final seen = <int>{};
      for (var noteId = 1; noteId <= 100; noteId++) {
        for (var slot = 0; slot <= 8; slot++) {
          final id = noteSlotId(noteId, slot);
          expect(seen.add(id), true,
              reason: 'trùng id $id (note $noteId slot $slot)');
          expect(id, greaterThanOrEqualTo(kNoteNotifBase));
        }
      }
      // Dải weather 1001–1006 nằm ngoài mọi id của notes.
      expect(seen.where((id) => id >= 1001 && id <= 1006), isEmpty);
    });

    test('allNoteSlotIds trả đủ 9 slot liên tiếp', () {
      expect(allNoteSlotIds(2), [for (var s = 0; s <= 8; s++) 10032 + s]);
    });
  });

  group('buildReminderSlots', () {
    // "now" cố định: Thứ 5, 02/07/2026 10:00 (Asia/Ho_Chi_Minh).
    final now = tz.TZDateTime(tz.local, 2026, 7, 2, 10, 0);

    test('một lần, tương lai → 1 slot 8, đúng mốc, không lặp', () {
      final slots = buildReminderSlots(
        _note(remindAt: DateTime(2026, 7, 3, 6, 30)),
        now,
      );
      expect(slots, hasLength(1));
      expect(slots.single.slot, 8);
      expect(slots.single.match, isNull);
      expect(slots.single.firstFire,
          tz.TZDateTime(tz.local, 2026, 7, 3, 6, 30));
    });

    test('một lần, đã qua → rỗng (không lập lịch quá khứ)', () {
      final slots = buildReminderSlots(
        _note(remindAt: DateTime(2026, 7, 1, 6, 30)),
        now,
      );
      expect(slots, isEmpty);
    });

    test('hằng ngày: giờ hôm nay đã qua → lùi sang mai; chưa qua → hôm nay',
        () {
      // 06:30 < now 10:00 → mai.
      final past = buildReminderSlots(
        _note(remindAt: DateTime(2026, 7, 2, 6, 30), repeat: NoteRepeat.daily),
        now,
      ).single;
      expect(past.slot, 8);
      expect(past.match, DateTimeComponents.time);
      expect(past.firstFire, tz.TZDateTime(tz.local, 2026, 7, 3, 6, 30));

      // 18:00 > now → hôm nay.
      final future = buildReminderSlots(
        _note(remindAt: DateTime(2026, 7, 2, 18, 0), repeat: NoteRepeat.daily),
        now,
      ).single;
      expect(future.firstFire, tz.TZDateTime(tz.local, 2026, 7, 2, 18, 0));
    });

    test('hằng tuần T2+T4 → 2 slot đúng thứ, tương lai, match dayOfWeekAndTime',
        () {
      final slots = buildReminderSlots(
        _note(
          remindAt: DateTime(2026, 7, 2, 7, 0),
          repeat: NoteRepeat.weekly,
          weekdaysMask: 0x05, // bit0 (T2) + bit2 (T4)
        ),
        now,
      );
      expect(slots.map((s) => s.slot).toList()..sort(), [1, 3]);
      for (final s in slots) {
        expect(s.match, DateTimeComponents.dayOfWeekAndTime);
        expect(s.firstFire.isAfter(now), true);
        expect(s.firstFire.weekday, s.slot);
        expect(s.firstFire.hour, 7);
      }
    });

    test('hằng tuần trùng thứ hôm nay nhưng giờ đã qua → nhảy sang tuần sau',
        () {
      // now = Thứ 5 (weekday 4) 10:00; nhắc Thứ 5 lúc 07:00 → 09/07.
      final slot = buildReminderSlots(
        _note(
          remindAt: DateTime(2026, 7, 2, 7, 0),
          repeat: NoteRepeat.weekly,
          weekdaysMask: 1 << 3, // Thứ 5
        ),
        now,
      ).single;
      expect(slot.firstFire, tz.TZDateTime(tz.local, 2026, 7, 9, 7, 0));
    });

    test('weekly mask 0 → rỗng; không remindAt → rỗng', () {
      expect(
        buildReminderSlots(
          _note(remindAt: DateTime(2026, 7, 3), repeat: NoteRepeat.weekly),
          now,
        ),
        isEmpty,
      );
      expect(buildReminderSlots(_note(), now), isEmpty);
    });
  });

  group('buildPinnedBody', () {
    test('render ☑/☐ theo thứ tự, kèm body', () {
      final body = buildPinnedBody(
        _note(body: 'Chuẩn bị cho chuyến đi'),
        [
          const NoteItem(noteId: 1, content: 'Hộ chiếu', done: true, seq: 0),
          const NoteItem(noteId: 1, content: 'Vé máy bay', seq: 1),
        ],
      );
      expect(body, 'Chuẩn bị cho chuyến đi\n☑ Hộ chiếu\n☐ Vé máy bay');
    });

    test('note chỉ có text → body nguyên vẹn, không dòng thừa', () {
      expect(buildPinnedBody(_note(body: 'Chỉ là lời nhắc'), const []),
          'Chỉ là lời nhắc');
    });
  });

  group('notePayload', () {
    test('round-trip qua parse', () {
      expect(parseNotePayload(notePayload(42)), 42);
      expect(parseNotePayload(null), isNull);
      expect(parseNotePayload('rác'), isNull);
      expect(parseNotePayload('{"khac":1}'), isNull);
    });
  });
}
