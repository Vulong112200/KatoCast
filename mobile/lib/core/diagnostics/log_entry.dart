import 'dart:convert';

/// Mức độ của một dòng nhật ký. Thứ tự index dùng làm giá trị lưu trong file
/// (`lvl`) nên KHÔNG được đổi thứ tự — chỉ thêm vào cuối.
enum LogLevel { info, warn, error }

/// Lớp/nguồn phát ra dòng nhật ký — trả lời câu "Ở ĐÂU": lớp trigger nào đang
/// chạy. Lưu dưới dạng chuỗi ngắn trong file (`src`) để đọc log thô vẫn hiểu.
class LogSource {
  const LogSource._();

  /// Foreground service (lớp chính giữ app sống).
  static const String fg = 'fg';

  /// Alarm exact backstop (`weather_alarm`).
  static const String alarm = 'alarm';

  /// Alarm heartbeat ban đêm (chỉ kiểm tra/sửa chuỗi, không lấy dữ liệu).
  static const String heartbeat = 'beat';

  /// WorkManager periodic.
  static const String worker = 'work';

  /// Alarm bản tin hằng ngày.
  static const String digest = 'digest';

  /// Alarm poll tin mới (JLPT/MBA…).
  static const String announce = 'announce';

  /// Main isolate / UI (mở app, đổi cài đặt, nút kiểm tra thủ công).
  static const String ui = 'ui';

  /// Nhãn tiếng Việt để hiển thị trên trang Nhật ký.
  static String label(String src) => switch (src) {
        fg => 'Foreground',
        alarm => 'Alarm nền',
        heartbeat => 'Heartbeat',
        worker => 'WorkManager',
        digest => 'Bản tin',
        announce => 'Tin mới',
        ui => 'Mở app',
        _ => src,
      };

  /// Các nguồn thuộc nhóm "chạy nền" (dùng cho filter chip trên trang Nhật ký).
  static const Set<String> backgroundSources = {
    fg,
    alarm,
    heartbeat,
    worker,
  };
}

/// Một dòng nhật ký đã parse. Thuần Dart (không phụ thuộc Flutter/Drift) để
/// dùng được ở mọi isolate.
class LogEntry {
  final DateTime ts;
  final LogLevel level;

  /// Xem [LogSource].
  final String source;

  /// Nhãn ngắn phân loại sự kiện trong một nguồn, vd `cycle`, `fetch`, `notify`.
  final String tag;
  final String message;

  /// Dữ liệu kèm theo (toạ độ, tuổi cache, thời lượng gọi API…). Rỗng nếu không.
  final Map<String, Object?> data;

  const LogEntry({
    required this.ts,
    required this.level,
    required this.source,
    required this.tag,
    required this.message,
    this.data = const {},
  });

  /// Dựng từ MỘT dòng JSONL. Trả null nếu dòng hỏng/không đủ trường — người gọi
  /// bỏ qua dòng đó thay vì để cả trang Nhật ký sập vì một dòng ghi dở (rất dễ
  /// xảy ra khi tiến trình bị OEM giết giữa lúc append).
  static LogEntry? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final json = jsonDecode(trimmed);
      if (json is! Map) return null;
      final tsMs = json['ts'];
      if (tsMs is! int) return null;
      final lvlIdx = json['lvl'];
      final level = (lvlIdx is int && lvlIdx >= 0 && lvlIdx < LogLevel.values.length)
          ? LogLevel.values[lvlIdx]
          : LogLevel.info;
      final rawData = json['data'];
      return LogEntry(
        ts: DateTime.fromMillisecondsSinceEpoch(tsMs),
        level: level,
        source: json['src']?.toString() ?? '?',
        tag: json['tag']?.toString() ?? '',
        message: json['msg']?.toString() ?? '',
        data: rawData is Map
            ? rawData.map((k, v) => MapEntry(k.toString(), v))
            : const {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Serialize thành MỘT dòng JSON (không chứa newline — người gọi tự thêm).
  String toJsonLine() => jsonEncode({
        'ts': ts.millisecondsSinceEpoch,
        'lvl': level.index,
        'src': source,
        'tag': tag,
        'msg': message,
        if (data.isNotEmpty) 'data': data,
      });

  /// Một dòng văn bản dễ đọc cho Copy/Chia sẻ, vd:
  /// `08:15:02 [alarm/cycle] bắt đầu chu kỳ · id=2001`
  String toDisplayLine() {
    final sb = StringBuffer()
      ..write(hhmmss)
      ..write(' ')
      ..write(switch (level) {
        LogLevel.info => '  ',
        LogLevel.warn => '! ',
        LogLevel.error => 'XX',
      })
      ..write(' [$source/$tag] ')
      ..write(message);
    if (data.isNotEmpty) {
      sb.write(' · ');
      sb.write(data.entries.map((e) => '${e.key}=${e.value}').join(' '));
    }
    return sb.toString();
  }

  /// "HH:mm:ss" theo giờ máy — không cần `intl`.
  String get hhmmss {
    final t = ts.toLocal();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Ngày dạng "dd/MM/yyyy" — dùng gom nhóm theo ngày trên trang Nhật ký.
  String get dayKey {
    final t = ts.toLocal();
    final d = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$d/$mo/${t.year}';
  }
}
