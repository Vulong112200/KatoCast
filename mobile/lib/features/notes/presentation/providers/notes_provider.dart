import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../shared/utils/error_handler.dart';
import '../../data/note_local_datasource.dart';
import '../../data/note_notification_service.dart';
import '../../domain/entities/note.dart';

// --- DI ---
final noteLocalDataSourceProvider = Provider<NoteLocalDataSource>(
  (ref) => NoteLocalDataSource(ref.watch(appDatabaseProvider)),
);

final noteNotificationServiceProvider = Provider<NoteNotificationService>(
  (ref) => NoteNotificationService(ref.watch(notificationServiceProvider)),
);

/// State màn Ghi chú: toàn bộ notes + checklist + query tìm kiếm.
class NotesState {
  final List<Note> notes; // tất cả, kể cả done
  final Map<int, List<NoteItem>> items; // noteId → checklist
  final String query;
  final bool loading;
  final String? error;

  const NotesState({
    this.notes = const [],
    this.items = const {},
    this.query = '',
    this.loading = true,
    this.error,
  });

  /// Notes đang hoạt động: lọc theo query, note ghim lên đầu.
  List<Note> get activeNotes {
    final list = notes.where((n) => !n.done && _matches(n)).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// Notes đã xong (khu lưu trữ), lọc theo query.
  List<Note> get doneNotes =>
      notes.where((n) => n.done && _matches(n)).toList();

  bool _matches(Note n) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (n.title.toLowerCase().contains(q)) return true;
    if (n.body.toLowerCase().contains(q)) return true;
    final its = items[n.id] ?? const [];
    return its.any((it) => it.content.toLowerCase().contains(q));
  }

  NotesState copyWith({
    List<Note>? notes,
    Map<int, List<NoteItem>>? items,
    String? query,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return NotesState(
      notes: notes ?? this.notes,
      items: items ?? this.items,
      query: query ?? this.query,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Quản lý ghi chú: CRUD + đồng bộ notification (ghim/lịch nhắc) qua một
/// phễu duy nhất `NoteNotificationService.sync`.
class NotesController extends StateNotifier<NotesState> {
  final NoteLocalDataSource _ds;
  final NoteNotificationService _notif;

  NotesController(this._ds, this._notif) : super(const NotesState()) {
    load();
  }

  Future<void> load() async {
    try {
      final notes = await _ds.getAllNotes();
      final items = await _ds.getAllItems();
      state = state.copyWith(
          notes: notes, items: items, loading: false, clearError: true);
    } catch (e, st) {
      debugPrint('Nạp ghi chú lỗi: $e\n$st');
      state = state.copyWith(loading: false, error: extractUserMessage(e));
    }
  }

  void setQuery(String q) => state = state.copyWith(query: q);

  /// Thêm mới / cập nhật note + checklist, rồi đồng bộ notification.
  Future<void> save(Note note, List<NoteItem> items) async {
    try {
      final now = DateTime.now();
      final toSave = note.copyWith(
        updatedAt: now,
        createdAt: note.id == null ? now : null,
      );
      final id = await _ds.upsertNote(toSave);
      await _ds.replaceItems(id, items);
      final saved = await _ds.getNote(id);
      if (saved != null) {
        await _notif.sync(saved, await _ds.getItems(id));
      }
      await load();
    } catch (e, st) {
      debugPrint('Lưu ghi chú lỗi: $e\n$st');
      state = state.copyWith(error: extractUserMessage(e));
    }
  }

  Future<void> togglePin(Note note) async {
    if (note.id == null) return;
    await _ds.setPinned(note.id!, !note.pinned);
    await _syncFromDb(note.id!);
    await load();
  }

  Future<void> toggleItemDone(NoteItem item) async {
    if (item.id == null) return;
    await _ds.setItemDone(item.id!, !item.done);
    // Note đang ghim → cập nhật ☑/☐ trên notification (re-show, cùng ID).
    final note = await _ds.getNote(item.noteId);
    if (note != null && note.pinned && !note.done) {
      await _notif.showPinned(note, await _ds.getItems(item.noteId));
    }
    await load();
  }

  /// Đánh dấu xong: gỡ ghim + huỷ mọi lịch, chuyển vào khu "Đã xong".
  Future<void> markDone(Note note) async {
    if (note.id == null) return;
    await _ds.setDone(note.id!, true);
    await _ds.setPinned(note.id!, false);
    await _notif.cancelAll(note.id!);
    await load();
  }

  /// Khôi phục từ khu "Đã xong" (không tự ghim/lập lịch lại — sync sẽ dựng
  /// lại theo trạng thái hiện tại: nhắc một lần quá khứ sẽ không lập).
  Future<void> restore(Note note) async {
    if (note.id == null) return;
    await _ds.setDone(note.id!, false);
    await _syncFromDb(note.id!);
    await load();
  }

  /// Xoá vĩnh viễn — huỷ notification/lịch TRƯỚC rồi mới xoá DB.
  Future<void> delete(Note note) async {
    if (note.id == null) return;
    await _notif.cancelAll(note.id!);
    await _ds.deleteNote(note.id!);
    await load();
  }

  Future<void> _syncFromDb(int id) async {
    final note = await _ds.getNote(id);
    if (note != null) {
      await _notif.sync(note, await _ds.getItems(id));
    }
  }
}

final notesControllerProvider =
    StateNotifierProvider<NotesController, NotesState>(
  (ref) => NotesController(
    ref.watch(noteLocalDataSourceProvider),
    ref.watch(noteNotificationServiceProvider),
  ),
);
