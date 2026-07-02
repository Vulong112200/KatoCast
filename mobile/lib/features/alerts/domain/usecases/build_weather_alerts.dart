import '../../../../core/config/app_config.dart';
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
/// Chống spam: chỉ phát khi trạng thái ĐỔI so với lần trước — NGOẠI LỆ: pha
/// mưa giữ nguyên nhưng THỜI ĐIỂM chuyển biến lệch ≥
/// `rainTimeShiftRenotifyMinutes` so với lần đã báo → phát bản "Cập nhật"
/// (cùng notification ID nên chỉ thay thế, không chồng chất).
///
/// Giờ HH:MM lấy trực tiếp từ `rain.changeAt` (timestamp dự báo tuyệt đối),
/// KHÔNG cộng phút vào giờ hiển thị — tránh drift khi dữ liệu là cache cũ.
/// Use case thuần → dễ test, dùng được cả foreground lẫn background isolate.
class BuildWeatherAlerts {
  const BuildWeatherAlerts();

  AlertResult call({
    required RainStatus rain,
    required WeatherCondition condition,
    required EnvChange env,
    RainPhase? previousPhase,
    WeatherCategory? previousCategory,
    DateTime? previousChangeAt,
    bool envAlreadyNotified = false,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final alerts = <WeatherAlert>[];

    // --- 1. Thời điểm mưa (timing) ---
    final phaseChanged = rain.phase != previousPhase;
    if (phaseChanged) {
      switch (rain.phase) {
        case RainPhase.rainStartingSoon:
          alerts.add(_rainStartAlert(rain, ref));
        case RainPhase.rainStoppingSoon:
          if (_wasRaining(previousPhase)) {
            alerts.add(_rainStopAlert(rain, ref));
          }
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
            alerts.add(WeatherAlert(
              id: NotificationIds.rainStart,
              title: 'Trời đang mưa',
              body: 'Hiện đang có mưa tại vị trí của bạn.'
                  '${_chanceSuffix(rain.probabilityPct, raining: true)} '
                  'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
            ));
          }
      }
    } else if (_shouldRenotifyTimeShift(rain, previousChangeAt)) {
      // Pha giữ nguyên nhưng thời điểm dự kiến lệch đáng kể → báo cập nhật.
      final updated = rain.phase == RainPhase.rainStartingSoon
          ? _rainStartAlert(rain, ref)
          : _rainStopAlert(rain, ref);
      alerts.add(WeatherAlert(
        id: updated.id,
        title: 'Cập nhật: ${updated.title}',
        body: updated.body,
      ));
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
      newChangeAt: rain.changeAt,
      envNotified: env.hasStrongChange,
    );
  }

  WeatherAlert _rainStartAlert(RainStatus rain, DateTime ref) => WeatherAlert(
        id: NotificationIds.rainStart,
        title: 'Sắp mưa tại khu vực của bạn',
        body: 'Dự kiến mưa ${_timingPhrase(rain, ref)} tại vị trí của '
            'bạn.${_chanceSuffix(rain.probabilityPct)} '
            'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
      );

  WeatherAlert _rainStopAlert(RainStatus rain, DateTime ref) => WeatherAlert(
        id: NotificationIds.rainStop,
        title: 'Mưa sắp tạnh',
        body: 'Mưa dự kiến tạnh ${_timingPhrase(rain, ref)}. '
            'Đường vẫn còn ướt, hãy di chuyển cẩn thận.',
      );

  /// Pha rainStartingSoon/rainStoppingSoon giữ nguyên nhưng thời điểm dự kiến
  /// lệch ≥ ngưỡng so với lần đã báo → cần báo lại.
  bool _shouldRenotifyTimeShift(RainStatus rain, DateTime? previousChangeAt) {
    if (rain.phase != RainPhase.rainStartingSoon &&
        rain.phase != RainPhase.rainStoppingSoon) {
      return false;
    }
    final at = rain.changeAt;
    if (at == null || previousChangeAt == null) return false;
    return at.difference(previousChangeAt).inMinutes.abs() >=
        AppConfig.rainTimeShiftRenotifyMinutes;
  }

  bool _wasRaining(RainPhase? p) =>
      p == RainPhase.raining || p == RainPhase.rainStoppingSoon;

  /// Cụm thời điểm: "lúc HH:MM (khoảng N phút tới)" từ timestamp dự báo,
  /// hoặc "ngay bây giờ" khi chuyển biến rơi vào slot hiện tại.
  String _timingPhrase(RainStatus rain, DateTime ref) {
    final at = rain.changeAt;
    if (at == null) {
      final n = rain.minutesUntilChange ?? 0;
      return n <= 0 ? 'ngay bây giờ' : 'trong khoảng $n phút tới';
    }
    final n = rain.minutesUntilChange ?? at.difference(ref).inMinutes;
    if (n <= 0) return 'ngay bây giờ';
    return 'lúc ${_clock(at)} (khoảng $n phút tới)';
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// Hậu tố " Khả năng mưa ~P%." nếu có dữ liệu xác suất; rỗng nếu không.
  String _chanceSuffix(int? pct, {bool raining = false}) {
    if (pct == null) return '';
    return raining
        ? ' Khả năng còn mưa khoảng $pct%.'
        : ' Khả năng mưa khoảng $pct%.';
  }
}

/// Kết quả: thông báo cần gửi + trạng thái mới để PERSIST (cho lần check sau).
class AlertResult {
  final List<WeatherAlert> alerts;
  final RainPhase newPhase;
  final WeatherCategory newCategory;

  /// Thời điểm chuyển biến đã dùng để báo (null nếu pha không có mốc) — lưu
  /// lại để lần sau so lệch giờ (báo "Cập nhật" khi lệch nhiều).
  final DateTime? newChangeAt;
  final bool envNotified;
  const AlertResult({
    required this.alerts,
    required this.newPhase,
    required this.newCategory,
    this.newChangeAt,
    required this.envNotified,
  });
}
