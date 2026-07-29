import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_log.dart';
import '../diagnostics/log_tags.dart';

/// Lock chống CHẠY CHỒNG một chu kỳ nền giữa các isolate.
///
/// Vấn đề nó giải quyết: foreground service, alarm exact backstop và WorkManager
/// chạy trong BA isolate khác nhau nhưng dùng chung một file SQLite, một
/// SharedPreferences và một hạn mức API. Khi hai lớp chạy cùng lúc:
/// - hai isolate cùng mở/ghi `katocast.sqlite` → `database is locked` (Drift
///   không hỗ trợ mở cùng một file DB từ nhiều isolate);
/// - cả hai đọc `AlertStateStore` TRƯỚC khi bên nào kịp ghi → cùng phát một cảnh
///   báo → người dùng nghe thông báo hai lần;
/// - tốn gấp đôi lượt gọi API.
///
/// Vì sao dùng FILE mà không dùng SharedPreferences: `SharedPreferences` giữ một
/// bản cache trong bộ nhớ RIÊNG của từng isolate, nên cờ do isolate này ghi thì
/// isolate kia không thấy — vô dụng cho việc loại trừ lẫn nhau. File thì mọi
/// isolate đọc cùng một nguồn sự thật.
///
/// Lock có HẠN: nếu chủ cũ bị OEM giết giữa chu kỳ thì `release` không bao giờ
/// chạy. Sau [staleAfter], lock được coi là bỏ hoang và bị chiếm lại (ghi log
/// warn) để app không tự khoá chết vĩnh viễn.
class CycleLock {
  const CycleLock._();

  static const String _fileName = 'bg_cycle.lock';

  /// Một chu kỳ nền bình thường mất vài giây. Quá ngưỡng này coi như chủ cũ đã
  /// chết (không phải "đang chạy chậm") và cho phép chiếm lại.
  static const Duration staleAfter = Duration(minutes: 3);

  static String? _path;

  /// Thử chiếm lock cho [owner] (dùng [LogSource] làm tên chủ).
  ///
  /// Trả `true` nếu chiếm được — người gọi PHẢI gọi [release] trong `finally`.
  /// Trả `false` nếu một chu kỳ khác đang chạy; khi đó người gọi nên bỏ lượt này
  /// **nhưng vẫn re-arm alarm của mình** để chuỗi không bị đứt.
  ///
  /// Không bao giờ ném lỗi: nếu tầng file lỗi thì trả `true` (thà chạy chồng như
  /// hiện trạng còn hơn ngừng cập nhật hoàn toàn).
  static Future<bool> tryAcquire(String owner) async {
    try {
      final path = await _resolvePath();
      if (path == null) return true;
      final file = File(path);

      if (await file.exists()) {
        final held = await _readHolder(file);
        if (held != null) {
          final age = DateTime.now().difference(held.at);
          if (age <= staleAfter) {
            await AppLog.i(
              owner,
              LogTags.lock,
              'bỏ lượt: chu kỳ đang chạy',
              data: {'chủ': held.owner, 'đã': '${age.inSeconds}s'},
            );
            return false;
          }
          await AppLog.w(
            owner,
            LogTags.lock,
            'chiếm lại lock quá hạn (chủ cũ có thể đã bị giết)',
            data: {'chủ': held.owner, 'đã': '${age.inMinutes}m'},
          );
        }
      }

      await file.writeAsString(
        '$owner|${DateTime.now().millisecondsSinceEpoch}',
        flush: true,
      );
      return true;
    } catch (e, st) {
      await AppLog.e(
        owner,
        LogTags.lock,
        'lỗi tầng lock → cho chạy tiếp (thà chồng hơn là ngừng cập nhật)',
        error: e,
        stack: st,
      );
      return true;
    }
  }

  /// Nhả lock. An toàn khi gọi nhiều lần / khi chưa từng chiếm được.
  static Future<void> release() async {
    try {
      final path = await _resolvePath();
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Không xoá được → lock sẽ tự hết hạn sau [staleAfter].
    }
  }

  /// Chạy [action] khi và chỉ khi chiếm được lock. Trả null nếu bỏ lượt.
  static Future<T?> runGuarded<T>(
    String owner,
    Future<T> Function() action,
  ) async {
    if (!await tryAcquire(owner)) return null;
    try {
      return await action();
    } finally {
      await release();
    }
  }

  static Future<({String owner, DateTime at})?> _readHolder(File file) async {
    try {
      final parts = (await file.readAsString()).split('|');
      if (parts.length != 2) return null;
      final ms = int.tryParse(parts[1]);
      if (ms == null) return null;
      return (owner: parts[0], at: DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _resolvePath() async {
    if (_path != null) return _path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      _path = p.join(docs.path, _fileName);
      return _path;
    } catch (_) {
      return null;
    }
  }

  /// Chỉ dùng cho TEST: trỏ lock vào thư mục tạm.
  static void debugOverrideDirectory(String dirPath) {
    _path = p.join(dirPath, _fileName);
  }
}
