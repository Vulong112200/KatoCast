import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/alerts/data/alert_state_store.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_daily_digest.dart';
import '../../features/alerts/domain/usecases/build_weather_alerts.dart';
import '../../features/location/domain/entities/coordinates.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../../features/weather/domain/entities/weather.dart';
import '../../features/weather/domain/entities/weather_condition.dart';
import '../../features/weather/domain/usecases/analyze_rain.dart';
import '../../features/weather/domain/usecases/detect_env_change.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';

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
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
    try {
      await _runWeatherCheck();
    } catch (_) {
      // Nuốt lỗi để WorkManager không retry dồn dập; lần sau sẽ check lại.
    }
    return true;
  });
}

Future<void> _runWeatherCheck() async {
  // 1. Vị trí: dùng last-known cho nhanh & tiết kiệm pin trong nền.
  final pos = await Geolocator.getLastKnownPosition();
  if (pos == null) return;
  // Bỏ qua nếu vị trí quá cũ → tránh cảnh báo nhầm khu vực người dùng đã rời đi.
  final age = DateTime.now().difference(pos.timestamp);
  if (age > const Duration(hours: AppConfig.backgroundLastKnownMaxAgeHours)) {
    return;
  }
  final coords = Coordinates(latitude: pos.latitude, longitude: pos.longitude);

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
      envNotified: out.envNotified,
    );

    // 6. Bản tin hằng ngày: nếu đang trong cửa sổ một mốc giờ và hôm nay chưa
    // gửi mốc đó → bắn 1 bản tin tóm tắt (độc lập với cảnh báo sự kiện).
    await _maybeSendDailyDigest(data, notif);
  } finally {
    await db.close();
  }
}

/// Bắn bản tin hằng ngày nếu đang trong cửa sổ của một mốc giờ (sáng/chiều) và
/// mốc đó hôm nay chưa được gửi. Dùng "đã gửi hôm nay" để chống lặp qua nhiều
/// lần chạy 15' trong cùng cửa sổ.
Future<void> _maybeSendDailyDigest(
  WeatherData data,
  NotificationService notif,
) async {
  final prefs = NotificationPrefsStore();
  final dp = await prefs.read();
  if (!dp.enabled) return;

  final now = DateTime.now();
  final nowMinutes = now.hour * 60 + now.minute;
  final today = now.year * 10000 + now.month * 100 + now.day;

  DailyDigest? digest;
  for (final slot in DigestSlot.values) {
    final start = dp.minutesOf(slot);
    final inWindow = nowMinutes >= start &&
        nowMinutes < start + AppConfig.digestWindowMinutes;
    if (!inWindow) continue;
    if (await prefs.lastSentDay(slot) == today) continue;

    digest ??= const BuildDailyDigest().call(data);
    await notif.init();
    await notif.show(
      id: NotificationIds.dailyDigest,
      title: digest.title,
      body: digest.body,
    );
    await prefs.markSent(slot, today);
  }
}
