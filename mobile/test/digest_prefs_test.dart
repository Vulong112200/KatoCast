import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/config/app_config.dart';
import 'package:katocast/core/notifications/notification_service.dart';
import 'package:katocast/features/alerts/data/notification_prefs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DigestPrefs.normalizeTimes', () {
    test('sort tăng dần + loại trùng', () {
      expect(
        DigestPrefs.normalizeTimes([990, 390, 990, 600]),
        [390, 600, 990],
      );
    });

    test('loại giá trị ngoài dải [0,1439]', () {
      expect(DigestPrefs.normalizeTimes([-10, 0, 1439, 1440, 5000]),
          [0, 1439]);
    });

    test('kẹp số lượng theo digestMaxSlots', () {
      final many = [for (var i = 0; i < 100; i++) i];
      final out = DigestPrefs.normalizeTimes(many);
      expect(out.length, AppConfig.digestMaxSlots);
    });
  });

  group('NotificationPrefsStore', () {
    test('mặc định (chưa có key) ⇒ 2 mốc mặc định 6:30 & 16:30', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await NotificationPrefsStore().read();
      expect(prefs.enabled, isTrue);
      expect(prefs.times, AppConfig.digestDefaultTimes);
    });

    test('migrate từ key CŨ (morning/evening) sang danh sách', () async {
      SharedPreferences.setMockInitialValues({
        'digest_morning_min': 420, // 7:00
        'digest_evening_min': 1080, // 18:00
      });
      final prefs = await NotificationPrefsStore().read();
      expect(prefs.times, [420, 1080]);

      // Đã ghi lại theo mô hình mới ⇒ đọc lần 2 không phụ thuộc key cũ.
      final again = await NotificationPrefsStore().read();
      expect(again.times, [420, 1080]);
    });

    test('setTimes rồi read: roundtrip + normalize', () async {
      SharedPreferences.setMockInitialValues({});
      final store = NotificationPrefsStore();
      await store.setTimes([990, 390, 390]); // trùng + chưa sort
      final prefs = await store.read();
      expect(prefs.times, [390, 990]);
    });

    test('setEnabled(false) được giữ qua read', () async {
      SharedPreferences.setMockInitialValues({});
      final store = NotificationPrefsStore();
      await store.setEnabled(false);
      final prefs = await store.read();
      expect(prefs.enabled, isFalse);
    });
  });

  group('Ánh xạ index ↔ alarm ID (digestBase + i)', () {
    test('mỗi mốc một ID liên tiếp, không đụng dải ghi chú (10000+)', () {
      final times = [390, 600, 990];
      final ids = [for (var i = 0; i < times.length; i++) NotificationIds.digestBase + i];
      expect(ids, [1100, 1101, 1102]);
      expect(ids.every((id) => id < 10000), isTrue);
      // Giải mã ngược: id → index.
      for (var i = 0; i < ids.length; i++) {
        expect(ids[i] - NotificationIds.digestBase, i);
      }
    });
  });
}
