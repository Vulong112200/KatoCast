import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/note.dart';

/// CRUD ghi chú trong Drift (bảng notes + note_items).
///
/// Nhận [AppDatabase] qua constructor nên dùng được ở cả main isolate
/// (qua `appDatabaseProvider`) lẫn background isolate (tự dựng `AppDatabase()`
/// — pattern như background_worker/digest_alarm).
class NoteLocalDataSource {
  final AppDatabase _db;
  NoteLocalDataSource(this._db);

  Future<List<Note>> getAllNotes() async {
    final rows = await (_db.select(_db.notes)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(_toNote).toList();
  }

  Future<Note?> getNote(int id) async {
    final row = await (_db.select(_db.notes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toNote(row);
  }

  /// Toàn bộ checklist, gom theo noteId (seq tăng dần).
  Future<Map<int, List<NoteItem>>> getAllItems() async {
    final rows = await (_db.select(_db.noteItems)
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    final map = <int, List<NoteItem>>{};
    for (final r in rows) {
      map.putIfAbsent(r.noteId, () => []).add(_toItem(r));
    }
    return map;
  }

  Future<List<NoteItem>> getItems(int noteId) async {
    final rows = await (_db.select(_db.noteItems)
          ..where((t) => t.noteId.equals(noteId))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    return rows.map(_toItem).toList();
  }

  /// Thêm mới (id == null) hoặc cập nhật; trả về id của note.
  Future<int> upsertNote(Note n) async {
    if (n.id == null) {
      return _db.into(_db.notes).insert(_toCompanion(n));
    }
    await (_db.update(_db.notes)..where((t) => t.id.equals(n.id!)))
        .write(_toCompanion(n));
    return n.id!;
  }

  /// Thay toàn bộ checklist của [noteId] (transaction: xoá hết + ghi lại
  /// theo thứ tự [items]).
  Future<void> replaceItems(int noteId, List<NoteItem> items) async {
    await _db.transaction(() async {
      await (_db.delete(_db.noteItems)..where((t) => t.noteId.equals(noteId)))
          .go();
      for (var i = 0; i < items.length; i++) {
        await _db.into(_db.noteItems).insert(NoteItemsCompanion.insert(
              noteId: noteId,
              content: items[i].content,
              done: Value(items[i].done),
              seq: i,
            ));
      }
    });
  }

  Future<void> setPinned(int id, bool v) => _touch(id, pinned: Value(v));

  Future<void> setDone(int id, bool v) => _touch(id, done: Value(v));

  Future<void> setItemDone(int itemId, bool v) async {
    await (_db.update(_db.noteItems)..where((t) => t.id.equals(itemId)))
        .write(NoteItemsCompanion(done: Value(v)));
  }

  /// Xoá note kèm toàn bộ checklist (transaction).
  Future<void> deleteNote(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.noteItems)..where((t) => t.noteId.equals(id))).go();
      await (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Các note đang ghim còn hoạt động (chưa done) — để re-assert notification.
  Future<List<Note>> getPinnedActive() async {
    final rows = await (_db.select(_db.notes)
          ..where((t) => t.pinned.equals(true) & t.done.equals(false)))
        .get();
    return rows.map(_toNote).toList();
  }

  /// Các note có hẹn giờ còn hoạt động — để re-sync lịch nhắc.
  Future<List<Note>> getWithReminders() async {
    final rows = await (_db.select(_db.notes)
          ..where((t) => t.remindAt.isNotNull() & t.done.equals(false)))
        .get();
    return rows.map(_toNote).toList();
  }

  // --- Helpers ---

  Future<void> _touch(
    int id, {
    Value<bool> pinned = const Value.absent(),
    Value<bool> done = const Value.absent(),
  }) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(pinned: pinned, done: done, updatedAt: Value(DateTime.now())),
    );
  }

  NotesCompanion _toCompanion(Note n) => NotesCompanion.insert(
        title: n.title,
        body: Value(n.body),
        colorIndex: Value(n.colorIndex),
        pinned: Value(n.pinned),
        done: Value(n.done),
        remindAt: Value(n.remindAt),
        repeat: Value(n.repeat.index),
        weekdaysMask: Value(n.weekdaysMask),
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
      );

  Note _toNote(NoteRow r) => Note(
        id: r.id,
        title: r.title,
        body: r.body,
        colorIndex: r.colorIndex,
        pinned: r.pinned,
        done: r.done,
        remindAt: r.remindAt,
        repeat: (r.repeat >= 0 && r.repeat < NoteRepeat.values.length)
            ? NoteRepeat.values[r.repeat]
            : NoteRepeat.none,
        weekdaysMask: r.weekdaysMask,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  NoteItem _toItem(NoteItemRow r) => NoteItem(
        id: r.id,
        noteId: r.noteId,
        content: r.content,
        done: r.done,
        seq: r.seq,
      );
}
