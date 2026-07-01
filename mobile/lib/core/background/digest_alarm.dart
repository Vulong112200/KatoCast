import 'package:connectivity_plus/connectivity_plus.dart';

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
/// dùng Riverpod. [id] chính là NotificationIds.dailyDigest{Morning,Evening}.
///
/// Khác cơ chế cũ (`zonedSchedule` bake sẵn text lúc lập lịch → hiển thị dữ
/// liệu cũ): callback này FETCH DỮ LIỆU TƯƠI ngay tại thời điểm bắn rồi mới
/// hiển thị, nên bản tin luôn phản ánh thời tiết hiện tại.
@pragma('vm:entry-point')
void digestAlarmCallback(int id) {
  _runDigest(id);
}

Future<void> _runDigest(int id) async {
  try {
    // Tôn trọng cài đặt: người dùng đã tắt bản tin thì không hiển thị.
    final prefs = await NotificationPrefsStore().read();
    if (!prefs.enabled) return;

    final coords = await resolveBackgroundCoords();
    if (coords == null) return;

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
  }
}
