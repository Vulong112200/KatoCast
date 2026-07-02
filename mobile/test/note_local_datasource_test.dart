import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/database/app_database.dart';
import 'package:katocast/features/notes/data/note_local_datasource.dart';
import 'package:katocast/features/notes/domain/entities/note.dart';

Note _note({
  int? id,
  String title = 'Đi du lịch',
  String body = 'Chuẩn bị hành lý',
  DateTime? remindAt,
  NoteRepeat repeat = NoteRepeat.none,
  int weekdaysMask = 0,
  bool pinned = false,
  bool done = false,
}) {
  final now = DateTime(2026, 7, 2, 10);
  return Note(
    id: id,
    title: title,
    body: body,
    colorIndex: 2,
    pinned: pinned,
    done: done,
    remindAt: remindAt,
    repeat: repeat,
    weekdaysMask: weekdaysMask,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late NoteLocalDataSource sut;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    sut = NoteLocalDataSource(db);
  });

  tearDown(() async => db.close());

  test('schema v2 tạo đủ 4 bảng (weather_cache, fixed_route_points, notes, note_items)',
      () async {
    // select trên từng bảng không ném lỗi = bảng tồn tại.
    await db.select(db.weatherCache).get();
    await db.select(db.fixedRoutePoints).get();
    await db.select(db.notes).get();
    await db.select(db.noteItems).get();
  });

  test('upsert: insert rồi round-trip đủ field', () async {
    final remind = DateTime(2026, 7, 3, 6, 0);
    final id = await sut.upsertNote(_note(
      remindAt: remind,
      repeat: NoteRepeat.weekly,
      weekdaysMask: 0x05, // T2 + T4
      pinned: true,
    ));

    final loaded = await sut.getNote(id);
    expect(loaded, isNotNull);
    expect(loaded!.title, 'Đi du lịch');
    expect(loaded.body, 'Chuẩn bị hành lý');
    expect(loaded.colorIndex, 2);
    expect(loaded.pinned, true);
    expect(loaded.done, false);
    expect(loaded.remindAt, remind);
    expect(loaded.repeat, NoteRepeat.weekly);
    expect(loaded.weekdaysMask, 0x05);
  });

  test('upsert: update giữ id, đổi nội dung + clear remindAt', () async {
    final id = await sut.upsertNote(_note(remindAt: DateTime(2026, 7, 3)));
    final loaded = (await sut.getNote(id))!;

    await sut.upsertNote(
        loaded.copyWith(title: 'Đổi tên', clearRemindAt: true));
    final updated = (await sut.getNote(id))!;
    expect(updated.title, 'Đổi tên');
    expect(updated.remindAt, isNull);
    expect((await sut.getAllNotes()).length, 1);
  });

  test('replaceItems giữ đúng thứ tự seq; deleteNote xoá kèm items', () async {
    final id = await sut.upsertNote(_note());
    await sut.replaceItems(id, [
      NoteItem(noteId: id, content: 'Hộ chiếu', seq: 0),
      NoteItem(noteId: id, content: 'Vé máy bay', done: true, seq: 0),
      NoteItem(noteId: id, content: 'Kem chống nắng', seq: 0),
    ]);

    final items = await sut.getItems(id);
    expect(items.map((e) => e.content).toList(),
        ['Hộ chiếu', 'Vé máy bay', 'Kem chống nắng']);
    expect(items.map((e) => e.seq).toList(), [0, 1, 2]);
    expect(items[1].done, true);

    await sut.deleteNote(id);
    expect(await sut.getNote(id), isNull);
    expect(await sut.getItems(id), isEmpty);
  });

  test('setPinned / setDone / setItemDone', () async {
    final id = await sut.upsertNote(_note());
    await sut.replaceItems(id, [NoteItem(noteId: id, content: 'A', seq: 0)]);

    await sut.setPinned(id, true);
    expect((await sut.getNote(id))!.pinned, true);

    await sut.setDone(id, true);
    expect((await sut.getNote(id))!.done, true);

    final item = (await sut.getItems(id)).single;
    await sut.setItemDone(item.id!, true);
    expect((await sut.getItems(id)).single.done, true);
  });

  test('getPinnedActive loại done; getWithReminders loại done + null remindAt',
      () async {
    await sut.upsertNote(_note(title: 'ghim sống', pinned: true));
    await sut.upsertNote(_note(title: 'ghim done', pinned: true, done: true));
    await sut.upsertNote(
        _note(title: 'nhắc sống', remindAt: DateTime(2026, 7, 5, 6)));
    await sut.upsertNote(_note(
        title: 'nhắc done', remindAt: DateTime(2026, 7, 5, 6), done: true));
    await sut.upsertNote(_note(title: 'thường'));

    final pinned = await sut.getPinnedActive();
    expect(pinned.map((n) => n.title), ['ghim sống']);

    final reminders = await sut.getWithReminders();
    expect(reminders.map((n) => n.title), ['nhắc sống']);
  });
}
