import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/alerts/data/alert_state_store.dart';
import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_weather_alerts.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../../features/weather/domain/entities/uv_advice.dart';
import '../../features/weather/domain/entities/weather.dart';
import '../../features/weather/domain/entities/weather_condition.dart';
import '../../features/weather/domain/usecases/analyze_rain.dart';
import '../../features/weather/domain/usecases/detect_env_change.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import 'background_location.dart';
import 'background_prefs.dart';

/// LÕI kiểm tra thời tiết nền — dùng CHUNG cho cả 3 lớp trigger:
/// foreground service (chính), alarm exact dự phòng, và WorkManager (backstop).
/// Chạy trong isolate riêng nên tự dựng dependency, KHÔNG dùng Riverpod.
///
/// GUARD QUOTA: OWM 4.0 tốn 3 call/refresh, giới hạn 1000/ngày. Vì nhiều
/// trigger cùng chạy ~15', hàm chỉ gọi API khi cache đã cũ ≥
/// `AppConfig.minRefreshGapMinutes`; nếu cache còn tươi thì dùng lại (không gọi
/// API) → các trigger trùng nhau tự khử. Lưu ý: `repo.getWeather` hiện luôn gọi
/// remote khi online (bỏ qua `forceRefresh`), nên guard PHẢI nằm ở đây.
///
/// Trả về [WeatherData] đã dùng (để caller như foreground service dựng nội dung
/// thông báo thường trực), hoặc null nếu không có dữ liệu (thiếu vị trí/offline
/// & chưa có cache).
Future<WeatherData?> runWeatherCheck() async {
  final coords = await resolveBackgroundCoords();
  if (coords == null) return null;

  final db = AppDatabase();
  try {
    final local = WeatherLocalDataSource(db);
    await local.purgeOlderThan(const Duration(days: AppConfig.cacheMaxAgeDays));

    final repo = WeatherRepositoryImpl(
      WeatherRemoteDataSource(ApiClient.create()),
      local,
      NetworkInfoImpl(Connectivity()),
    );

    // Guard quota bám theo chu kỳ người dùng chọn: cache còn tươi hơn (chu kỳ −
    // 1') → không gọi API. Trước đây guard cứng 12' nhằm khử trùng lặp giữa 3
    // lớp trigger; nay chỉ MỘT lớp chạy tại một thời điểm, nên guard chỉ cần
    // ngăn double-fire lúc chuyển giao và cho phép chu kỳ ngắn (5') thật sự làm
    // mới mỗi 5'.
    final interval = await BackgroundPrefsStore().intervalMinutes();
    final gapMinutes = interval > 1 ? interval - 1 : interval;
    final cached = await repo.getCachedWeather(coords);
    WeatherData? data;
    if (cached != null && cached.age.inMinutes < gapMinutes) {
      data = cached;
    } else {
      final result = await repo.getWeather(coords);
      data = result.fold((_) => null, (d) => d);
    }
    if (data == null) return null;

    // Các side-effect (sinh cảnh báo + lập lịch bản tin) được bọc try/catch
    // RIÊNG để một lỗi ở đây KHÔNG làm mất `data`. Quan trọng với foreground
    // service: nó cần `data` trả về để cập nhật thông báo thường trực — trước
    // đây `scheduleDigests` ném lỗi trong isolate nền khiến `runWeatherCheck`
    // văng, `data` không về tới `_tick`, thông báo kẹt mãi ở text khởi tạo.
    try {
      // Dữ liệu quá cũ (fetch fail → cache cũ) → KHÔNG sinh cảnh báo để tránh
      // báo pha/giờ sai; vẫn đảm bảo lịch bản tin ở bước cuối.
      if (data.age.inMinutes <= AppConfig.alertMaxDataAgeMinutes) {
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
          previousNotifiedAt: prev.notifiedAt,
          envAlreadyNotified: prev.envNotified,
        );

        final notif = NotificationService();
        if (out.alerts.isNotEmpty) {
          await notif.init();
          for (final a in out.alerts) {
            await notif.show(id: a.id, title: a.title, body: a.body);
          }
        }

        await store.write(
          phase: out.newPhase,
          category: out.newCategory,
          changeAt: out.newChangeAt,
          notifiedAt: out.newNotifiedAt,
          envNotified: out.envNotified,
        );
      }

      // Bản tin hằng ngày: đảm bảo alarm đã lập đúng mốc theo cài đặt hiện tại.
      final dp = await NotificationPrefsStore().read();
      await scheduleDigests(dp);
    } catch (_) {
      // Nuốt lỗi side-effect; `data` vẫn được trả về bên dưới.
    }

    return data;
  } finally {
    await db.close();
  }
}

/// Nội dung ngắn cho thông báo thường trực của foreground service, ví dụ
/// "🌤️ 33°C · Trời nắng · UV 8 · cập nhật 14:35". Dùng `WeatherCondition` để
/// lấy emoji; kèm giờ lấy dữ liệu (`fetchedAt`) để tiện theo dõi độ tươi —
/// biết được thông báo phản ánh lần gọi API/cache lúc nào.
String foregroundStatusText(WeatherData data) {
  final c = data.current;
  final condition = WeatherCondition.classify(c.conditionId, rainMmH: c.rain1h);
  final uv = UvAdvice.classify(c.uvi);
  return '${condition.emoji} ${c.tempC.round()}°C · ${condition.label} '
      '· UV ${uv.level} · cập nhật ${_hhmm(data.fetchedAt)}';
}

/// Định dạng giờ "HH:mm" theo giờ máy (thủ công, không cần `intl`).
String _hhmm(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
