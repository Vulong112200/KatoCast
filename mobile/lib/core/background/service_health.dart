import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_log.dart';
import '../diagnostics/log_tags.dart';
import '../notifications/notification_service.dart';
import 'background_prefs.dart';

/// Theo dõi "foreground service còn sống không" xuyên qua ranh giới isolate.
///
/// ⚠️ Vì sao cần một store riêng thay vì cứ hồi sinh service như trước:
/// isolate nền **KHÔNG ĐƯỢC PHÉP** start foreground service trên Android 12+.
/// Bản cũ vẫn thử, và hậu quả nặng hơn nhiều so với "không hồi sinh được":
/// `flutter_foreground_task` gọi `startForeground()` trong `onStartCommand`
/// KHÔNG có try/catch, nên `ForegroundServiceStartNotAllowedException` bay lên
/// luồng chính của tiến trình → **tiến trình CHẾT**. Nhật ký thật 02/08 cho thấy
/// đúng chuỗi đó: 12:58, 13:13, 13:28, 13:43, 14:13, 14:28 — mỗi lần ghi
/// "thử hồi sinh" rồi im lặng tuyệt đối, không có cả dòng lỗi. Sau vài lần sập
/// liên tiếp, hệ thống force-stop app → hủy SẠCH alarm + job của WorkManager →
/// app đứng im **46 tiếng** (02/08 14:28 → 04/08 12:33) tới khi người dùng mở
/// app. Đây là nguyên nhân gốc của "dùng càng lâu, càng không restart máy thì
/// càng lỗi".
///
/// Nay isolate nền chỉ GHI NHẬN việc service đã chết. Việc bật lại được làm ở
/// nơi hợp pháp duy nhất: khi app hiển thị với người dùng (xem `main.dart`
/// `onResume` → `applyBackgroundTriggers`). Ngoài ra, im lặng quá lâu thì phát
/// MỘT thông báo nhắc mở app — biến một sự cố vô hình thành thứ người dùng
/// khắc phục được trong một lần chạm.
class ForegroundServiceHealth {
  const ForegroundServiceHealth._();

  static const String _kDeadSinceMs = 'fg_service_dead_since_ms';
  static const String _kNudgeLastMs = 'fg_service_nudge_last_ms';

  /// Chết lâu hơn ngưỡng này (trong khung giờ hoạt động) thì mới nhắc — dưới
  /// ngưỡng thì alarm + WorkManager vẫn cập nhật đủ tốt, không đáng làm phiền.
  static const Duration nudgeAfter = Duration(hours: 2);

  /// Giãn cách tối thiểu giữa hai lần nhắc.
  static const Duration nudgeCooldown = Duration(hours: 6);

  /// Service đang chạy → xoá mốc chết (và mốc nhắc, để lần sự cố sau được nhắc
  /// ngay khi đủ điều kiện thay vì mắc cooldown cũ).
  static Future<void> markAlive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getInt(_kDeadSinceMs) == null) return;
      await prefs.remove(_kDeadSinceMs);
      await prefs.remove(_kNudgeLastMs);
    } catch (_) {
      // Không ghi được thì cùng lắm là nhắc trễ — không đáng làm sập chu kỳ.
    }
  }

  /// Service đã chết → ghi mốc lần ĐẦU phát hiện (giữ nguyên nếu đã có, để biết
  /// đã im lặng bao lâu). Trả về khoảng thời gian đã chết.
  static Future<Duration?> markDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final since = prefs.getInt(_kDeadSinceMs);
      if (since == null) {
        await prefs.setInt(_kDeadSinceMs, nowMs);
        return Duration.zero;
      }
      return Duration(milliseconds: nowMs - since);
    } catch (_) {
      return null;
    }
  }

  /// Service đã chết bao lâu (null = đang chạy / chưa từng ghi nhận). Chỉ ĐỌC,
  /// không ghi gì — dùng cho trang Nhật ký hoạt động.
  static Future<Duration?> deadFor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final since = prefs.getInt(_kDeadSinceMs);
      if (since == null) return null;
      return Duration(
        milliseconds: DateTime.now().millisecondsSinceEpoch - since,
      );
    } catch (_) {
      return null;
    }
  }

  /// Đã tới lúc nhắc người dùng mở app chưa (và ghi lại mốc nhắc nếu có).
  static Future<bool> _claimNudge(Duration deadFor) async {
    if (deadFor < nudgeAfter) return false;
    if (!await isWithinActiveHours(DateTime.now())) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastMs = prefs.getInt(_kNudgeLastMs) ?? 0;
      if (lastMs != 0 && nowMs - lastMs < nudgeCooldown.inMilliseconds) {
        return false;
      }
      await prefs.setInt(_kNudgeLastMs, nowMs);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ghi nhận trạng thái service từ một isolate NỀN và nhắc nếu im lặng quá lâu.
  ///
  /// [running] = kết quả `FlutterForegroundTask.isRunningService`.
  /// KHÔNG bao giờ start service ở đây — xem lý do ở đầu file.
  static Future<void> reportFromBackground(
    String source, {
    required bool running,
  }) async {
    if (running) {
      await markAlive();
      await AppLog.i(
          source, LogTags.service, 'foreground service vẫn đang chạy');
      return;
    }

    final deadFor = await markDead();
    await AppLog.w(
      source,
      LogTags.service,
      'foreground service ĐÃ CHẾT — KHÔNG hồi sinh từ nền (Android 12+ chặn, '
      'và plugin sập tiến trình nếu thử) → alarm + WorkManager vẫn cập nhật',
      data: {
        'đã chết': deadFor == null ? 'chưa rõ' : _fmt(deadFor),
        'bật lại khi': 'bạn mở app (đường duy nhất được hệ thống cho phép)',
      },
    );

    if (deadFor == null || !await _claimNudge(deadFor)) return;
    try {
      await NotificationService().showServiceHealth(
        id: NotificationIds.serviceHealth,
        title: 'Kato tạm ngừng theo dõi liên tục 🐾',
        body: 'Hệ thống đã dừng chế độ theo dõi thời tiết liên tục '
            '(${_fmt(deadFor)} trước). App vẫn cập nhật theo chu kỳ nhưng có thể '
            'chậm hơn. Mở KatoAssistant một lần để bật lại theo dõi liên tục.',
      );
      await AppLog.i(
        source,
        LogTags.notify,
        'ĐÃ BÁO: nhắc mở app để bật lại theo dõi liên tục',
        data: {'id': NotificationIds.serviceHealth, 'đã chết': _fmt(deadFor)},
      );
    } catch (e, st) {
      await AppLog.e(source, LogTags.notify, 'không gửi được nhắc nhở service',
          error: e, stack: st);
    }
  }

  /// Gỡ thông báo nhắc (gọi khi service đã sống lại) — để nó không nằm lại trên
  /// khay nói một chuyện đã được sửa.
  static Future<void> clearNudgeNotification() async {
    try {
      await NotificationService().cancel(NotificationIds.serviceHealth);
    } catch (_) {
      // Không gỡ được thì thôi; thông báo này im lặng, không gây hại.
    }
  }

  static String _fmt(Duration d) {
    if (d.inMinutes < 1) return 'vừa xong';
    if (d.inHours < 1) return '${d.inMinutes} phút';
    return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }
}
