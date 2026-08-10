import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Khoá SharedPreferences lưu TÊN múi giờ địa phương (vd `Asia/Ho_Chi_Minh`).
///
/// Isolate main ghi lại mỗi lần khởi động; isolate nền đọc ra khi kênh platform
/// của `flutter_timezone` không trả lời được. Nhờ đó `tz.local` luôn đúng thay
/// vì im lặng rơi về UTC (lệch 7 tiếng ở VN).
const String kLocalTimezoneNameKey = 'local_timezone_name';

/// Đã nạp CSDL múi giờ trong ISOLATE NÀY chưa (static ⇒ riêng từng isolate).
bool _dbLoaded = false;

/// Đã set được `tz.local` chưa. Tách khỏi [_dbLoaded] để trường hợp không lấy
/// được tên múi giờ (mạng/kênh platform chưa sẵn) còn được THỬ LẠI ở chu kỳ sau,
/// thay vì kẹt ở UTC suốt đời isolate — mà vẫn không nạp lại CSDL mỗi lần.
bool _localSet = false;

/// Khởi tạo cơ sở dữ liệu múi giờ + `tz.local`. **Idempotent**, an toàn gọi ở
/// MỌI isolate, và KHÔNG BAO GIỜ ném lỗi ra ngoài.
///
/// ⚠️ VÌ SAO CẦN: `tz.local` là một `late final` của package `timezone` — chưa
/// `setLocalLocation` mà đọc nó là ném `LateInitializationError`. Trước đây chỉ
/// `main()` khởi tạo, nên MỌI isolate nền (foreground service, alarm exact,
/// WorkManager) đều nổ ngay khi chạm tới lịch nhắc ghi chú:
///
/// ```
/// lỗi re-assert ghim ghi chú
/// err: LateInitializationError: Field '_local@345310200' has not been initialized.
///   at #0 _local (package:timezone/src/env.dart)
///      #2 NoteNotificationService._scheduleReminders
///         (package:katocast/features/notes/data/note_notification_service.dart:171)
/// ```
///
/// Nhật ký thật 05–06/08/2026 ghi lỗi này ở CẢ BA lớp nền (Foreground 09:38:21 /
/// 13:53:22, Alarm nền 13:30:21 / 13:45:21, WorkManager 12:41:33 / 13:26:39) —
/// **74 lỗi trong 24 giờ**, và hệ quả thật là: lịch nhắc ghi chú KHÔNG BAO GIỜ
/// được dựng lại từ nền (sau reboot hoặc sau khi người dùng "Xoá tất cả"), vì
/// `reassertNoteNotifications` chết ngay ở note đầu tiên có mốc nhắc.
Future<void> ensureTimezoneInitialized() async {
  if (_localSet) return;
  try {
    if (!_dbLoaded) {
      tzdata.initializeTimeZones();
      _dbLoaded = true;
    }

    // Ưu tiên hỏi hệ thống; isolate nền thiếu kênh platform thì đọc tên đã lưu.
    String? name;
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      // Không hỏi được → dùng đường dự phòng bên dưới.
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (name != null && name.isNotEmpty) {
        await prefs.setString(kLocalTimezoneNameKey, name);
      } else {
        // reload: giá trị do isolate main ghi, isolate này giữ cache riêng.
        await prefs.reload();
        name = prefs.getString(kLocalTimezoneNameKey);
      }
    } catch (_) {
      // Không đọc/ghi được prefs → vẫn thử set bằng `name` đang có (nếu có).
    }

    if (name != null && name.isNotEmpty) {
      tz.setLocalLocation(tz.getLocation(name));
      _localSet = true;
    }
    // Không có tên múi giờ nào: KHÔNG set và KHÔNG chốt cờ → chu kỳ sau thử lại
    // (tz.local tạm là UTC nên lịch nhắc lệch, nhưng app không sập). Lần khởi
    // động kế tiếp isolate main ghi tên vào prefs nên nền tự chữa được.
  } catch (_) {
    // Khởi tạo múi giờ thất bại KHÔNG được làm chết chu kỳ nền.
  }
}
