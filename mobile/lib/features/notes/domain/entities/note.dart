/// Kiểu lặp của lịch nhắc ghi chú. Lưu DB bằng `.index` — KHÔNG đổi thứ tự.
enum NoteRepeat {
  /// Nhắc đúng một lần tại `remindAt`.
  none,

  /// Lặp mỗi ngày vào giờ:phút của `remindAt`.
  daily,

  /// Lặp hằng tuần vào các thứ trong `weekdaysMask`, giờ:phút của `remindAt`.
  weekly,
}

/// Ghi chú cá nhân: text thuần hoặc kèm checklist, có thể ghim sticky lên
/// thanh thông báo và/hoặc hẹn giờ nhắc.
class Note {
  final int? id; // null = chưa lưu DB
  final String title;
  final String body;

  /// Index vào bảng màu note (kNoteColors); 0 = mặc định theo theme.
  final int colorIndex;

  /// Đang ghim sticky trên thanh thông báo.
  final bool pinned;

  /// Đã xong (khu lưu trữ) — không hiện notification nào.
  final bool done;

  /// Thời điểm nhắc; null = không hẹn giờ.
  final DateTime? remindAt;
  final NoteRepeat repeat;

  /// Bit (weekday-1) theo `DateTime.weekday`: bit0=Thứ 2 … bit6=Chủ nhật.
  final int weekdaysMask;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    this.id,
    required this.title,
    this.body = '',
    this.colorIndex = 0,
    this.pinned = false,
    this.done = false,
    this.remindAt,
    this.repeat = NoteRepeat.none,
    this.weekdaysMask = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasReminder => remindAt != null;

  Note copyWith({
    int? id,
    String? title,
    String? body,
    int? colorIndex,
    bool? pinned,
    bool? done,
    DateTime? remindAt,
    bool clearRemindAt = false,
    NoteRepeat? repeat,
    int? weekdaysMask,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      colorIndex: colorIndex ?? this.colorIndex,
      pinned: pinned ?? this.pinned,
      done: done ?? this.done,
      remindAt: clearRemindAt ? null : (remindAt ?? this.remindAt),
      repeat: repeat ?? this.repeat,
      weekdaysMask: weekdaysMask ?? this.weekdaysMask,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Một mục trong checklist của ghi chú.
class NoteItem {
  final int? id;
  final int noteId;
  final String content;
  final bool done;

  /// Thứ tự hiển thị.
  final int seq;

  const NoteItem({
    this.id,
    required this.noteId,
    required this.content,
    this.done = false,
    required this.seq,
  });

  NoteItem copyWith({
    int? id,
    int? noteId,
    String? content,
    bool? done,
    int? seq,
  }) {
    return NoteItem(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      content: content ?? this.content,
      done: done ?? this.done,
      seq: seq ?? this.seq,
    );
  }
}
