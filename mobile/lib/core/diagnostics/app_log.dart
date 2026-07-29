import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import 'log_entry.dart';

/// Nhật ký hoạt động BỀN của app — ghi ra **file JSONL**, không ghi vào Drift.
///
/// Vì sao file mà không phải DB: nhật ký này tồn tại chính để chẩn đoán các lỗi
/// tầng dữ liệu (DB bị lock giữa các isolate, fetch thất bại). Nếu nó ghi vào
/// cùng file SQLite đang tranh chấp thì đúng lúc cần log nhất lại là lúc không
/// ghi được. Append vào file text còn cho phép nhiều isolate (foreground service,
/// alarm, WorkManager, main) ghi song song mà không cần phối hợp lock.
///
/// Dùng được ở MỌI isolate: API static, không phụ thuộc Riverpod.
///
/// NGUYÊN TẮC: **không bao giờ ném lỗi ra ngoài**. Ghi log không được là thứ làm
/// hỏng một chu kỳ nền — mọi lỗi I/O đều bị nuốt tại đây (đây là chỗ DUY NHẤT
/// trong codebase được phép nuốt lỗi trần).
class AppLog {
  const AppLog._();

  static const String _fileName = 'kato.log';
  static const String _rotatedName = 'kato.1.log';
  static const String _dirName = 'logs';

  /// Đường dẫn file hiện hành (cache sau lần phân giải đầu — mỗi isolate một lần).
  static String? _path;
  static String? _rotatedPath;

  /// Kích thước xấp xỉ của file hiện hành, để khỏi `stat()` mỗi lần ghi.
  static int _approxSize = -1;

  /// Chuỗi hoá các lượt ghi TRONG CÙNG isolate (giữa các isolate thì dựa vào
  /// append mode của OS). Ngăn hai lượt ghi trong cùng isolate đan nhau.
  static Future<void> _queue = Future.value();

  /// Ghi mức thông tin.
  static Future<void> i(
    String source,
    String tag,
    String message, {
    Map<String, Object?>? data,
  }) =>
      _write(LogLevel.info, source, tag, message, data);

  /// Ghi mức cảnh báo (bất thường nhưng đã xử lý được).
  static Future<void> w(
    String source,
    String tag,
    String message, {
    Map<String, Object?>? data,
  }) =>
      _write(LogLevel.warn, source, tag, message, data);

  /// Ghi mức lỗi. [error]/[stack] được gộp vào `data` để trang Nhật ký hiển thị
  /// được nguyên nhân thật thay vì chỉ một câu chung chung.
  static Future<void> e(
    String source,
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?>? data,
  }) {
    final merged = <String, Object?>{
      ...?data,
      if (error != null) 'err': error.toString(),
      // Chỉ giữ vài dòng đầu của stack: đủ định vị, không làm phình file.
      if (stack != null) 'at': _shortStack(stack),
    };
    return _write(LogLevel.error, source, tag, message, merged);
  }

  static Future<void> _write(
    LogLevel level,
    String source,
    String tag,
    String message,
    Map<String, Object?>? data,
  ) {
    final entry = LogEntry(
      ts: DateTime.now(),
      level: level,
      source: source,
      tag: tag,
      message: message,
      data: _compact(data),
    );
    // Nối vào hàng đợi của isolate; mọi lỗi bị nuốt để chuỗi không bị đứt.
    final queued = _queue.then((_) => _append(entry)).catchError((_) {});
    _queue = queued;
    return queued;
  }

  static Future<void> _append(LogEntry entry) async {
    try {
      final path = await _resolvePath();
      if (path == null) return;
      final line = '${entry.toJsonLine()}\n';
      await _rotateIfNeeded(path, line.length);
      await File(path).writeAsString(line, mode: FileMode.writeOnlyAppend, flush: true);
      if (_approxSize >= 0) _approxSize += line.length;
    } catch (_) {
      // I/O lỗi (hết chỗ, quyền, tiến trình bị giết giữa lúc ghi) → bỏ dòng này.
    }
  }

  /// Vượt ngưỡng kích thước → dồn file hiện hành sang `kato.1.log` (ghi đè bản
  /// cũ) và bắt đầu file mới. Giữ đúng 2 file nên dung lượng có trần cứng.
  static Future<void> _rotateIfNeeded(String path, int incomingBytes) async {
    try {
      final file = File(path);
      if (_approxSize < 0) {
        _approxSize = await file.exists() ? await file.length() : 0;
      }
      if (_approxSize + incomingBytes <= AppConfig.logMaxBytesPerFile) return;
      if (await file.exists()) {
        final rotated = File(_rotatedPath!);
        if (await rotated.exists()) await rotated.delete();
        await file.rename(_rotatedPath!);
      }
      _approxSize = 0;
    } catch (_) {
      // Không rotate được → cứ ghi tiếp, lần sau thử lại.
      _approxSize = 0;
    }
  }

  static Future<String?> _resolvePath() async {
    if (_path != null) return _path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, _dirName));
      if (!await dir.exists()) await dir.create(recursive: true);
      _path = p.join(dir.path, _fileName);
      _rotatedPath = p.join(dir.path, _rotatedName);
      return _path;
    } catch (_) {
      return null;
    }
  }

  /// Đọc toàn bộ nhật ký còn trong hạn, MỚI NHẤT TRƯỚC.
  ///
  /// Tự áp hai giới hạn của [AppConfig]: bỏ dòng cũ hơn `logRetentionDays` và
  /// cắt còn `logMaxEntries` dòng gần nhất. Dòng hỏng bị bỏ qua (xem
  /// [LogEntry.tryParse]) nên một lần ghi dở không làm sập trang Nhật ký.
  static Future<List<LogEntry>> readAll() async {
    final entries = <LogEntry>[];
    try {
      final path = await _resolvePath();
      if (path == null) return entries;
      final cutoff = DateTime.now()
          .subtract(const Duration(days: AppConfig.logRetentionDays));
      // Đọc file đã dồn TRƯỚC rồi tới file hiện hành → thứ tự thời gian tăng.
      for (final f in [File(_rotatedPath!), File(path)]) {
        if (!await f.exists()) continue;
        for (final line in await f.readAsLines()) {
          final entry = LogEntry.tryParse(line);
          if (entry == null || entry.ts.isBefore(cutoff)) continue;
          entries.add(entry);
        }
      }
    } catch (_) {
      // Đọc lỗi → trả về những gì đã đọc được.
    }
    entries.sort((a, b) => b.ts.compareTo(a.ts)); // mới nhất trước
    if (entries.length > AppConfig.logMaxEntries) {
      return entries.sublist(0, AppConfig.logMaxEntries);
    }
    return entries;
  }

  /// Xoá sạch nhật ký (cả file đã dồn).
  static Future<void> clear() async {
    try {
      final path = await _resolvePath();
      if (path == null) return;
      for (final f in [File(path), File(_rotatedPath!)]) {
        if (await f.exists()) await f.delete();
      }
      _approxSize = 0;
    } catch (_) {}
  }

  /// Kết xuất dạng văn bản để Copy / gửi đi.
  static Future<String> exportText() async {
    final entries = await readAll();
    final sb = StringBuffer()
      ..writeln('KatoAssistant — nhật ký hoạt động')
      ..writeln('Kết xuất lúc: ${DateTime.now().toLocal()}')
      ..writeln('Số dòng: ${entries.length}')
      ..writeln('---');
    String? day;
    // Xuất theo thứ tự CŨ → MỚI để đọc như một dòng thời gian.
    for (final entry in entries.reversed) {
      if (entry.dayKey != day) {
        day = entry.dayKey;
        sb..writeln()..writeln('=== $day ===');
      }
      sb.writeln(entry.toDisplayLine());
    }
    return sb.toString();
  }

  /// Chỉ dùng cho TEST: trỏ nhật ký vào một thư mục tạm.
  static void debugOverrideDirectory(String dirPath) {
    _path = p.join(dirPath, _fileName);
    _rotatedPath = p.join(dirPath, _rotatedName);
    _approxSize = -1;
    _queue = Future.value();
  }

  /// Chờ mọi lượt ghi đang chờ trong isolate này hoàn tất. Gọi trước khi một
  /// isolate nền kết thúc để không mất dòng cuối.
  static Future<void> flush() => _queue.catchError((_) {});

  /// Bỏ các khoá có giá trị null để dòng JSON gọn (và `data` rỗng thì bỏ hẳn).
  static Map<String, Object?> _compact(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return const {};
    final out = <String, Object?>{};
    for (final e in data.entries) {
      if (e.value != null) out[e.key] = e.value;
    }
    return out;
  }

  static String _shortStack(StackTrace stack) {
    final lines = stack.toString().split('\n');
    return lines.take(3).map((l) => l.trim()).where((l) => l.isNotEmpty).join(' | ');
  }
}
