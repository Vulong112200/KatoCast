import '../../../../core/notifications/notification_service.dart';
import '../../../weather/domain/entities/rain_status.dart';
import '../../../weather/domain/entities/weather_condition.dart';
import '../../../weather/domain/usecases/detect_env_change.dart';
import '../entities/weather_alert.dart';

/// Sinh danh sách thông báo cá nhân hóa dựa trên trạng thái MỚI so với LẦN TRƯỚC.
///
/// 3 nhóm thông báo:
/// 1. Thời điểm mưa (bắt đầu/tạnh) — từ `RainStatus` (minutely, chính xác phút).
/// 2. Tình hình thời tiết (nắng/mây/mưa nhỏ-to/dông-bão) — từ `WeatherCondition`.
/// 3. Thay đổi môi trường mạnh (nhiệt/ẩm) — từ `EnvChange`.
///
/// Chống spam: chỉ phát khi trạng thái ĐỔI so với lần trước. Use case thuần →
/// dễ test, dùng được cả foreground lẫn background isolate.
class BuildWeatherAlerts {
  const BuildWeatherAlerts();

  AlertResult call({
    required RainStatus rain,
    required WeatherCondition condition,
    required EnvChange env,
    RainPhase? previousPhase,
    WeatherCategory? previousCategory,
    bool envAlreadyNotified = false,
  }) {
    final alerts = <WeatherAlert>[];

    // --- 1. Thời điểm mưa (timing) — chỉ khi pha đổi ---
    if (rain.phase != previousPhase) {
      switch (rain.phase) {
        case RainPhase.rainStartingSoon:
          final n = rain.minutesUntilChange ?? 0;
          alerts.add(WeatherAlert(
            id: NotificationIds.rainStart,
            title: 'Sắp mưa tại khu vực của bạn',
            body: 'Dự kiến trời sẽ mưa trong $n phút tới tại vị trí của bạn. '
                'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
          ));
        case RainPhase.rainStoppingSoon:
        case RainPhase.dry:
          if (_wasRaining(previousPhase)) {
            alerts.add(const WeatherAlert(
              id: NotificationIds.rainStop,
              title: 'Trời đã tạnh mưa',
              body: 'Trời đã tạnh mưa tại khu vực của bạn, đường vẫn còn ướt, '
                  'hãy di chuyển cẩn thận.',
            ));
          }
        case RainPhase.raining:
          if (!_wasRaining(previousPhase)) {
            alerts.add(const WeatherAlert(
              id: NotificationIds.rainStart,
              title: 'Trời đang mưa',
              body: 'Hiện đang có mưa tại vị trí của bạn. '
                  'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
            ));
          }
      }
    }

    // --- 2. Tình hình thời tiết (nắng/mây/mưa/bão) — chỉ khi nhóm đổi ---
    if (condition.category != previousCategory) {
      alerts.add(WeatherAlert(
        id: NotificationIds.condition,
        title: '${condition.emoji} ${condition.label}',
        body: condition.advice.isNotEmpty
            ? condition.advice
            : 'Tình hình thời tiết hiện tại: ${condition.label}.',
      ));
    }

    // --- 3. Thay đổi môi trường mạnh — chỉ phát 1 lần cho tới khi hết mạnh ---
    if (env.hasStrongChange && !envAlreadyNotified) {
      alerts.add(const WeatherAlert(
        id: NotificationIds.envChange,
        title: 'Thời tiết đang thay đổi mạnh',
        body: 'Độ ẩm/Nhiệt độ hiện tại đang thay đổi mạnh, '
            'chú ý không gian sống và thú cưng.',
      ));
    }

    return AlertResult(
      alerts: alerts,
      newPhase: rain.phase,
      newCategory: condition.category,
      envNotified: env.hasStrongChange,
    );
  }

  bool _wasRaining(RainPhase? p) =>
      p == RainPhase.raining || p == RainPhase.rainStoppingSoon;
}

/// Kết quả: thông báo cần gửi + trạng thái mới để PERSIST (cho lần check sau).
class AlertResult {
  final List<WeatherAlert> alerts;
  final RainPhase newPhase;
  final WeatherCategory newCategory;
  final bool envNotified;
  const AlertResult({
    required this.alerts,
    required this.newPhase,
    required this.newCategory,
    required this.envNotified,
  });
}
