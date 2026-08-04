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

  /// Token của lượt chiếm HIỆN TẠI của isolate này (null = không giữ lock).
  ///
  /// ⚠️ Vì sao cần token: [release] cũ xoá file lock VÔ ĐIỀU KIỆN. Kịch bản sai:
  /// chu kỳ A bị treo quá [staleAfter] → B chiếm lại lock (đúng) → A tỉnh lại,
  /// chạy `finally { release() }` và **xoá lock của B** → một chu kỳ thứ ba chen
  /// vào giữa lúc B đang mở DB. Đó chính là loại tranh chấp mà lock này tồn tại
  /// để ngăn. Nay chỉ chủ THẬT SỰ của lock mới xoá được.
  static String? _heldToken;

  /// Bộ đếm để token không trùng khi hai lượt chiếm rơi vào cùng micro-giây.
  static int _tokenSeq = 0;

  /// Thử chiếm lock cho [owner] (dùng [LogSource] làm tên chủ).
  ///
  /// Trả `true` nếu chiếm được — người gọi PHẢI gọi [release] trong `finally`.
  /// Trả `false` nếu một chu kỳ khác đang chạy; khi đó người gọi nên bỏ lượt này
  /// **nhưng vẫn re-arm alarm của mình** để chuỗi không bị đứt.
  ///
  /// Không bao giờ ném lỗi: nếu tầng file lỗi thì trả `true` (thà chạy chồng như
  /// hiện trạng còn hơn ngừng cập nhật hoàn toàn).
  /// [quiet] = true khi đang thăm dò trong vòng chờ của [runWaiting] — không ghi
  /// log mỗi nhịp, tránh làm ngập nhật ký bằng hàng chục dòng "bỏ lượt".
  static Future<bool> tryAcquire(String owner, {bool quiet = false}) async {
    try {
      final path = await _resolvePath();
      if (path == null) return true;
      final file = File(path);

      if (await file.exists()) {
        final held = await _readHolder(file);
        if (held != null) {
          final age = DateTime.now().difference(held.at);
          if (age <= staleAfter) {
            if (!quiet) {
              await AppLog.i(
                owner,
                LogTags.lock,
                'bỏ lượt: chu kỳ đang chạy',
                data: {'chủ': held.owner, 'đã': '${age.inSeconds}s'},
              );
            }
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

      final token = '$owner-${DateTime.now().microsecondsSinceEpoch}-'
          '${_tokenSeq++}';
      await file.writeAsString(
        '$owner|${DateTime.now().millisecondsSinceEpoch}|$token',
        flush: true,
      );
      _heldToken = token;
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

  /// Nhả lock — CHỈ khi lock trên đĩa vẫn là lượt chiếm của isolate này.
  ///
  /// An toàn khi gọi nhiều lần / khi chưa từng chiếm được. Nếu lock đã bị lớp
  /// khác chiếm lại (chu kỳ này chạy quá [staleAfter]) thì KHÔNG xoá — xem
  /// [_heldToken].
  static Future<void> release() async {
    try {
      final path = await _resolvePath();
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) {
        _heldToken = null;
        return;
      }
      final held = await _readHolder(file);
      // Token null = file định dạng CŨ (trước khi có token) → giữ hành vi cũ:
      // xoá, vì không có cách nào biết chủ. Có token thì phải khớp.
      if (held?.token != null && held!.token != _heldToken) {
        await AppLog.w(
          held.owner,
          LogTags.lock,
          'KHÔNG nhả lock: lock đã thuộc chu kỳ khác (chu kỳ này chạy quá lâu '
          'và đã bị chiếm lại) — xoá sẽ mở đường cho chu kỳ thứ ba chen vào',
        );
        _heldToken = null;
        return;
      }
      await file.delete();
      _heldToken = null;
    } catch (_) {
      // Không xoá được → lock sẽ tự hết hạn sau [staleAfter].
    }
  }

  /// Thời gian CHỜ tối đa của [runWaiting] trước khi chạy bất chấp lock.
  static const Duration defaultWait = Duration(seconds: 75);

  /// Nhịp thăm dò lock khi đang chờ.
  static const Duration _pollInterval = Duration(seconds: 3);

  /// Chạy [action] khi và chỉ khi chiếm được lock. Trả null nếu bỏ lượt.
  ///
  /// Dành cho các chu kỳ LẶP LẠI (foreground tick, alarm backstop, WorkManager):
  /// bỏ một lượt không mất gì vì vài phút sau lại có lượt khác.
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

  /// Chạy [action] sau khi CHỜ lock tối đa [wait]; hết thời gian chờ thì **vẫn
  /// chạy** (ghi log warn).
  ///
  /// Dành cho việc CHỈ XẢY RA MỘT LẦN trong ngày và người dùng ĐANG ĐỢI: bản tin
  /// hằng ngày và lượt poll tin mới. Với chúng, `runGuarded` là sai — đây là bug
  /// thật đã quan sát được: bản tin 6:30 nổ đúng lúc WorkManager đang giữ lock,
  /// bị bỏ lượt rồi tự hẹn lại NGÀY MAI → mất hẳn bản tin của ngày đó.
  ///
  /// Lock ở đây chỉ để giảm tranh chấp DB, không phải bất biến về đúng đắn — nên
  /// khi phải chọn, ưu tiên GIAO ĐƯỢC thông báo cho người dùng.
  static Future<T> runWaiting<T>(
    String owner,
    Future<T> Function() action, {
    Duration wait = defaultWait,
  }) async {
    final deadline = DateTime.now().add(wait);
    var acquired = await tryAcquire(owner);
    if (!acquired) {
      await AppLog.i(owner, LogTags.lock,
          'chu kỳ khác đang chạy → CHỜ tối đa ${wait.inSeconds}s (không bỏ lượt)');
    }
    while (!acquired && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);
      acquired = await tryAcquire(owner, quiet: true);
    }
    if (!acquired) {
      await AppLog.w(
        owner,
        LogTags.lock,
        'chờ lock quá ${wait.inSeconds}s → CHẠY BẤT CHẤP '
        '(thà tranh chấp DB còn hơn mất thông báo của người dùng)',
      );
    }
    try {
      return await action();
    } finally {
      // Chỉ nhả khi thật sự đang giữ — nếu chạy bất chấp thì lock thuộc về lớp
      // khác, xoá đi sẽ mở đường cho một chu kỳ thứ ba chen vào.
      if (acquired) await release();
    }
  }

  /// Đọc chủ lock. Định dạng `owner|millis|token`; vẫn đọc được định dạng CŨ
  /// `owner|millis` (file còn sót lại sau khi cập nhật app) với `token == null`.
  static Future<({String owner, DateTime at, String? token})?> _readHolder(
    File file,
  ) async {
    try {
      final parts = (await file.readAsString()).split('|');
      if (parts.length < 2 || parts.length > 3) return null;
      final ms = int.tryParse(parts[1]);
      if (ms == null) return null;
      return (
        owner: parts[0],
        at: DateTime.fromMillisecondsSinceEpoch(ms),
        token: parts.length == 3 ? parts[2] : null,
      );
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
    _heldToken = null;
  }
}
