import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/exam_event.dart';
import 'event_remote_data_source.dart';

/// Nối backend (lịch chuẩn) + Drift `event_overrides` (bản sửa/thêm của người
/// dùng). Bản sửa tay LUÔN ưu tiên và được đánh dấu `isUserVerified`.
class EventRepository {
  final EventRemoteDataSource _remote;
  final AppDatabase _db;

  EventRepository(this._remote, this._db);

  /// Lấy lịch đã merge cho [topics]. Backend lỗi mạng → vẫn trả các event
  /// người dùng tự thêm/sửa (offline-friendly).
  Future<List<ExamEvent>> fetchMerged(List<String> topics) async {
    final backend = <ExamEvent>[];
    for (final t in topics) {
      try {
        backend.addAll(await _remote.fetch(topic: t));
      } catch (_) {
        // 1 topic lỗi không chặn topic khác / bản local.
      }
    }

    final overrides = await _db.select(_db.eventOverrides).get();
    final bySource = <int, EventOverrideRow>{};
    final custom = <EventOverrideRow>[];
    for (final o in overrides) {
      if (o.sourceEventId != null) {
        bySource[o.sourceEventId!] = o;
      } else {
        custom.add(o);
      }
    }

    final merged = <ExamEvent>[];
    for (final e in backend) {
      final ov = e.backendId != null ? bySource[e.backendId!] : null;
      merged.add(ov == null ? e : _applyOverride(e, ov));
    }
    for (final o in custom) {
      merged.add(_fromOverride(o));
    }

    merged.sort((a, b) {
      final ax = a.examDate, bx = b.examDate;
      if (ax == null && bx == null) return 0;
      if (ax == null) return 1; // null xuống cuối
      if (bx == null) return -1;
      return bx.compareTo(ax); // mới/tương lai trước
    });
    return merged;
  }

  ExamEvent _applyOverride(ExamEvent base, EventOverrideRow o) => base.copyWith(
        overrideId: o.id,
        regStart: o.regStart,
        regEnd: o.regEnd,
        examDate: o.examDate,
        resultDate: o.resultDate,
        note: o.note,
        isUserVerified: true,
        updatedAt: o.updatedAt,
      );

  ExamEvent _fromOverride(EventOverrideRow o) => ExamEvent(
        overrideId: o.id,
        topic: o.topic,
        sessionLabel: o.sessionLabel,
        regStart: o.regStart,
        regEnd: o.regEnd,
        examDate: o.examDate,
        resultDate: o.resultDate,
        note: o.note,
        isUserVerified: true,
        updatedAt: o.updatedAt,
      );

  /// Lưu bản sửa cho một event (backend hoặc custom). Với event backend, ghi đè
  /// theo `sourceEventId`; với custom (backendId null) tạo/ cập nhật theo overrideId.
  Future<void> saveOverride(ExamEvent e) async {
    final companion = EventOverridesCompanion.insert(
      sourceEventId: Value(e.backendId),
      topic: Value(e.topic),
      sessionLabel: e.sessionLabel,
      regStart: Value(e.regStart),
      regEnd: Value(e.regEnd),
      examDate: Value(e.examDate),
      resultDate: Value(e.resultDate),
      note: Value(e.note),
      updatedAt: DateTime.now(),
    );

    if (e.backendId != null) {
      // unique(sourceEventId) → cập nhật nếu đã có bản sửa.
      final existing = await (_db.select(_db.eventOverrides)
            ..where((t) => t.sourceEventId.equals(e.backendId!)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.eventOverrides)
              ..where((t) => t.id.equals(existing.id)))
            .write(companion);
        return;
      }
    } else if (e.overrideId != null) {
      await (_db.update(_db.eventOverrides)
            ..where((t) => t.id.equals(e.overrideId!)))
          .write(companion);
      return;
    }
    await _db.into(_db.eventOverrides).insert(companion);
  }

  Future<void> deleteOverride(int overrideId) async {
    await (_db.delete(_db.eventOverrides)..where((t) => t.id.equals(overrideId)))
        .go();
  }
}
