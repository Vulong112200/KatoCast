import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/alerts/data/alert_state_store.dart';
import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_weather_alerts.dart';
import '../../features/notes/data/note_notification_service.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../../features/weather/domain/entities/weather_condition.dart';
import '../../features/weather/domain/usecases/analyze_rain.dart';
import '../../features/weather/domain/usecases/detect_env_change.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import 'background_location.dart';

const String kWeatherCheckTask = 'katocast.weatherCheck';

/// Đăng ký task định kỳ. Gọi 1 lần lúc app khởi động.
class BackgroundScheduler {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      kWeatherCheckTask,
      kWeatherCheckTask,
      frequency: const Duration(minutes: AppConfig.backgroundIntervalMinutes),
      constraints: Constraints(networkType: NetworkType.connected),
      // `update`: áp cấu hình mới lên task đã đăng ký từ lần cài trước (với
      // `keep`, các thay đổi ở đây sẽ không có hiệu lực trên máy đã cài).
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Tiện ích debug: chạy ngay 1 lần để test notification.
  static Future<void> runOnceNow() async {
    await Workmanager().registerOneOffTask(
      '$kWeatherCheckTask.once',
      kWeatherCheckTask,
    );
  }
}

/// Entry-point chạy trong background isolate. KHÔNG dùng Riverpod ở đây —
/// isolate này không chia sẻ state với main isolate, nên tự dựng dependency.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kWeatherCheckTask) return true;
    // Ghi chú ghim: re-assert TRƯỚC (try riêng, DB riêng) — hồi phục sau
    // reboot/"Xoá tất cả" kể cả khi không có vị trí (guard coords của weather
    // không được chặn bước này).
    try {
      await _reassertNotes();
    } catch (_) {}
    try {
      await _runWeatherCheck();
    } catch (_) {
      // Nuốt lỗi để WorkManager không retry dồn dập; lần sau sẽ check lại.
    }
    return true;
  });
}

Future<void> _reassertNotes() async {
  final db = AppDatabase();
  try {
    await reassertNoteNotifications(db, NotificationService());
  } finally {
    await db.close();
  }
}

Future<void> _runWeatherCheck() async {
  // 1. Vị trí: last-known (hoặc toạ độ đã lưu nếu last-known hết hạn).
  final coords = await resolveBackgroundCoords();
  if (coords == null) return;

  // 2. Dựng dependency cục bộ cho isolate.
  final db = AppDatabase();
  try {
    final local = WeatherLocalDataSource(db);
    // Dọn cache cũ định kỳ (mỗi chu kỳ background) để DB không phình.
    await local.purgeOlderThan(
      const Duration(days: AppConfig.cacheMaxAgeDays),
    );

    final repo = WeatherRepositoryImpl(
      WeatherRemoteDataSource(ApiClient.create()),
      local,
      NetworkInfoImpl(Connectivity()),
    );

    final result = await repo.getWeather(coords, forceRefresh: true);
    final data = result.fold((_) => null, (d) => d);
    if (data == null) return; // offline & không có cache → bỏ qua lần này.

    // Dữ liệu quá cũ (fetch fail → repo trả cache) → KHÔNG sinh cảnh báo để
    // tránh báo pha/giờ sai; vẫn đảm bảo lịch bản tin ở bước cuối.
    if (data.age.inMinutes <= AppConfig.alertMaxDataAgeMinutes) {
      // 3. Phân tích + so trạng thái cũ → sinh thông báo.
      final rain = const AnalyzeRain().call(data);
      final env = const DetectEnvChange().call(data);
      final condition = WeatherCondition.classify(
        data.current.conditionId,
        rainMmH: data.current.rain1h,
      );

      final store = AlertStateStore();
      final prev = await store.read();

      final out = const BuildWeatherAlerts().call(
        rain: rain,
        condition: condition,
        env: env,
        previousPhase: prev.phase,
        previousCategory: prev.category,
        previousChangeAt: prev.changeAt,
        envAlreadyNotified: prev.envNotified,
      );

      // 4. Gửi notification cảnh báo sự kiện.
      final notif = NotificationService();
      if (out.alerts.isNotEmpty) {
        await notif.init();
        for (final a in out.alerts) {
          await notif.show(id: a.id, title: a.title, body: a.body);
        }
      }

      // 5. Lưu trạng thái cho lần sau.
      await store.write(
        phase: out.newPhase,
        category: out.newCategory,
        changeAt: out.newChangeAt,
        envNotified: out.envNotified,
      );
    }

    // 6. Bản tin hằng ngày: đảm bảo alarm hệ thống đã được lập đúng mốc giờ
    // theo cài đặt hiện tại. Nội dung KHÔNG bake ở đây — callback alarm tự
    // fetch dữ liệu tươi ngay lúc bắn (kể cả khi app đã tắt).
    final dp = await NotificationPrefsStore().read();
    await scheduleDigests(dp);
  } finally {
    await db.close();
  }
}
