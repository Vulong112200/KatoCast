import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_daily_digest.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import 'background_location.dart';

/// Entry-point do AndroidAlarmManager gọi ĐÚNG mốc giờ bản tin (kể cả khi app
/// đã tắt / màn hình tắt). Chạy trong isolate riêng → tự dựng dependency, KHÔNG
/// dùng Riverpod. [id] = `NotificationIds.digestBase + index`, với `index` là
/// vị trí mốc trong danh sách [DigestPrefs.times] (đã sort).
///
/// Khác cơ chế cũ (`zonedSchedule` bake sẵn text lúc lập lịch → hiển thị dữ
/// liệu cũ): callback này FETCH DỮ LIỆU TƯƠI ngay tại thời điểm bắn rồi mới
/// hiển thị, nên bản tin luôn phản ánh thời tiết hiện tại.
///
/// Vì lịch dùng `oneShotAt` (không tự lặp — cần thiết để nổ đúng giờ trong
/// Doze), callback PHẢI tự đặt lại mốc cho ngày mai ở cuối (kể cả khi bỏ hiển
/// thị vì thiếu vị trí/offline), trừ khi bản tin đã tắt hoặc mốc đã bị xóa.
@pragma('vm:entry-point')
void digestAlarmCallback(int id) {
  if (id == NotificationIds.digestTest) {
    _runDigestTest();
    return;
  }
  _runDigest(id);
}

/// Bản tin THỬ: chỉ hiển thị một thông báo xác nhận (KHÔNG fetch thời tiết,
/// KHÔNG re-arm, KHÔNG phụ thuộc bản tin bật/tắt) → cô lập đúng khâu giao alarm
/// nền để người dùng tự chẩn đoán force-stop.
Future<void> _runDigestTest() async {
  try {
    final notif = NotificationService();
    await notif.init();
    await notif.show(
      id: NotificationIds.digestTest,
      title: '✅ Thông báo nền hoạt động',
      body: 'Bản tin thử đã nổ đúng giờ. Nếu bạn VUỐT TẮT app mà thông báo này '
          'KHÔNG xuất hiện, hãy bật "Tự khởi động" + đặt pin "Không giới hạn".',
    );
  } catch (_) {}
}

Future<void> _runDigest(int id) async {
  DigestPrefs? prefs;
  try {
    // Tôn trọng cài đặt: người dùng đã tắt bản tin thì không hiển thị (và
    // không re-arm — xử lý ở finally theo prefs.enabled).
    prefs = await NotificationPrefsStore().read();
    if (!prefs.enabled) return;

    final coords = await resolveBackgroundCoords();
    if (coords == null) return; // vẫn re-arm ở finally cho ngày mai.

    final db = AppDatabase();
    try {
      final repo = WeatherRepositoryImpl(
        WeatherRemoteDataSource(ApiClient.create()),
        WeatherLocalDataSource(db),
        NetworkInfoImpl(Connectivity()),
      );
      // forceRefresh: cố lấy tươi; offline sẽ fallback cache trong repo.
      final result = await repo.getWeather(coords, forceRefresh: true);
      final data = result.fold((_) => null, (d) => d);
      if (data == null) return; // offline & không có cache → bỏ mốc này.

      final digest = const BuildDailyDigest().call(data);
      final notif = NotificationService();
      await notif.init();
      await notif.show(id: id, title: digest.title, body: digest.body);
    } finally {
      await db.close();
    }
  } catch (_) {
    // Nuốt lỗi để alarm không kẹt; mốc kế tiếp (ngày mai) sẽ thử lại.
  } finally {
    // Đặt lại alarm cho ngày mai (one-shot không tự lặp). Chỉ khi bản tin còn
    // bật VÀ mốc (index) này vẫn tồn tại trong danh sách. Bọc try riêng để lỗi
    // hiển thị không chặn việc re-arm.
    try {
      final p = prefs ?? await NotificationPrefsStore().read();
      final index = id - NotificationIds.digestBase;
      if (p.enabled && index >= 0 && index < p.times.length) {
        await scheduleDigestSlot(id, p.times[index]);
      }
    } catch (e) {
      // Không nuốt trần: log để chẩn đoán chuỗi alarm bị đứt. Mạng an toàn:
      // `scheduleDigests` (idempotent) được gọi lại mỗi chu kỳ nền sẽ chữa lại.
      debugPrint('KatoCast: re-arm bản tin (id=$id) lỗi: $e');
    }
  }
}
