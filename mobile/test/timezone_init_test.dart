import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/notifications/timezone_init.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Bảo vệ cho lỗi nặng nhất trong nhật ký 05–06/08/2026 (74 lỗi/24h):
/// isolate nền không chạy `main()` nên `tz.local` chưa được set, và MỌI chu kỳ
/// nền chết ở `NoteNotificationService._scheduleReminders` với
/// `LateInitializationError: Field '_local@…' has not been initialized`.
///
/// Ở môi trường test, kênh platform của `flutter_timezone` không tồn tại — đúng
/// tình huống của isolate nền — nên test này chạy thẳng vào đường dự phòng đọc
/// tên múi giờ từ SharedPreferences (do isolate main ghi lúc khởi động).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('không có kênh platform ⇒ dùng tên múi giờ đã lưu, tz.local dùng được',
      () async {
    SharedPreferences.setMockInitialValues({
      kLocalTimezoneNameKey: 'Asia/Ho_Chi_Minh',
    });

    await ensureTimezoneInitialized();

    expect(tz.local.name, 'Asia/Ho_Chi_Minh');
    // Chính lời gọi đã nổ trong nhật ký thật (note_notification_service.dart:171).
    expect(() => tz.TZDateTime.now(tz.local), returnsNormally);
    // +07:00 — nếu rơi về UTC thì lịch nhắc ghi chú sẽ bắn lệch 7 tiếng.
    expect(tz.TZDateTime(tz.local, 2026, 8, 6, 6, 30).timeZoneOffset,
        const Duration(hours: 7));
  });

  test('gọi lại nhiều lần là vô hại (idempotent)', () async {
    SharedPreferences.setMockInitialValues({
      kLocalTimezoneNameKey: 'Asia/Ho_Chi_Minh',
    });
    await ensureTimezoneInitialized();
    await ensureTimezoneInitialized();
    expect(tz.local.name, 'Asia/Ho_Chi_Minh');
  });
}
