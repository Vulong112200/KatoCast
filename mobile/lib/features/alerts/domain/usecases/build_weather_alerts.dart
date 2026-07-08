import '../../../../core/config/app_config.dart';
import '../../../../core/kato/kato_voice.dart';
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
/// Chống spam: chỉ phát khi trạng thái ĐỔI so với lần trước — 2 NGOẠI LỆ khi
/// pha mưa giữ nguyên:
/// - Thời điểm chuyển biến lệch đáng kể so với lần ĐÃ BÁO (sớm hơn ≥
///   `rainTimeShiftRenotifyMinutes`, hoặc muộn hơn ≥
///   `rainTimeShiftLaterRenotifyMinutes`) → bản "Cập nhật" (cùng ID → thay thế).
/// - Đã báo "sắp mưa" từ XA, nay cơn mưa áp sát còn ≤ `rainReminderLeadMinutes`
///   → MỘT bản nhắc lại (trả lời nhu cầu "báo trước ~30 phút").
///
/// Trạng thái persist (`newChangeAt`/`newNotifiedAt`) chỉ cập nhật khi có
/// thông báo mưa THẬT SỰ được phát — nếu ghi đè mỗi chu kỳ thì dự báo "trôi"
/// dần 5–10 phút/lần sẽ không bao giờ vượt ngưỡng báo lại (bug cũ).
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
    DateTime? previousNotifiedAt,
    bool envAlreadyNotified = false,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final alerts = <WeatherAlert>[];

    // --- 1. Thời điểm mưa (timing) ---
    final phaseChanged = rain.phase != previousPhase;
    var rainAlertFired = false;
    if (phaseChanged) {
      switch (rain.phase) {
        case RainPhase.rainStartingSoon:
          alerts.add(_rainStartAlert(rain, ref));
          rainAlertFired = true;
        case RainPhase.rainStoppingSoon:
          if (_wasRaining(previousPhase)) {
            alerts.add(_rainStopAlert(rain, ref));
            rainAlertFired = true;
          }
        case RainPhase.dry:
          if (_wasRaining(previousPhase)) {
            alerts.add(WeatherAlert(
              id: NotificationIds.rainStop,
              title: 'Trời đã tạnh mưa',
              body: '${KatoVoice.cleared(ref.minute)}'
                  'Trời đã tạnh mưa tại khu vực của bạn, đường vẫn còn ướt, '
                  'hãy di chuyển cẩn thận.',
            ));
            rainAlertFired = true;
          }
        case RainPhase.raining:
          if (!_wasRaining(previousPhase)) {
            alerts.add(WeatherAlert(
              id: NotificationIds.rainStart,
              title: 'Trời đang mưa',
              body: '${KatoVoice.raining(ref.minute)}'
                  'Hiện đang có mưa tại vị trí của bạn.'
                  '${_chanceSuffix(rain.probabilityPct, raining: true)} '
                  'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
            ));
            rainAlertFired = true;
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
      rainAlertFired = true;
    } else if (_shouldRemindOnsetClose(rain, previousChangeAt,
        previousNotifiedAt, ref)) {
      // Đã báo từ xa, cơn mưa nay áp sát → nhắc lại một lần (cùng ID).
      final base = _rainStartAlert(rain, ref);
      alerts.add(WeatherAlert(
        id: base.id,
        title: 'Sắp mưa: còn khoảng ${rain.minutesUntilChange} phút',
        body: base.body,
      ));
      rainAlertFired = true;
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
      alerts.add(WeatherAlert(
        id: NotificationIds.envChange,
        title: 'Thời tiết đang thay đổi mạnh',
        body: '${KatoVoice.envChange(ref.minute)}'
            'Độ ẩm/Nhiệt độ hiện tại đang thay đổi mạnh, '
            'chú ý không gian sống và thú cưng.',
      ));
    }

    return AlertResult(
      alerts: alerts,
      newPhase: rain.phase,
      newCategory: condition.category,
      // Chỉ chốt mốc mới khi pha đổi hoặc đã phát thông báo mưa; nếu không,
      // GIỮ mốc đã báo lần trước để lần sau còn so lệch được (chống drift).
      newChangeAt:
          (phaseChanged || rainAlertFired) ? rain.changeAt : previousChangeAt,
      newNotifiedAt: rainAlertFired ? ref : previousNotifiedAt,
      envNotified: env.hasStrongChange,
    );
  }

  WeatherAlert _rainStartAlert(RainStatus rain, DateTime ref) => WeatherAlert(
        id: NotificationIds.rainStart,
        title: 'Sắp mưa tại khu vực của bạn',
        body: '${KatoVoice.rainIncoming(ref.minute)}'
            'Dự kiến mưa ${_timingPhrase(rain, ref)} tại vị trí của '
            'bạn.${_chanceSuffix(rain.probabilityPct)}'
            '${_courseSuffix(rain)} '
            'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
      );

  /// Hậu tố mô tả cơn mưa kéo dài/diễn biến ra sao:
  /// - ≥2 đoạn cường độ → mô tả từng đoạn ("mưa vừa ~17:00–19:00, sau đó mưa
  ///   nhỏ ~19:00–21:00") thay vì một khối dài gây hiểu lầm mưa to suốt.
  /// - 1 đoạn nhưng chỉ suy từ xác suất giờ (possible) → nói mềm "có thể có
  ///   mưa rải rác đến ...".
  /// - còn lại → "Dự kiến kéo dài đến khoảng HH:MM (~N phút)."
  /// Rỗng nếu không xác định được giờ tạnh và không có diễn biến.
  String _courseSuffix(RainStatus rain) {
    final course = describeRainCourse(rain.segments);
    if (course != null) return ' Diễn biến: $course.';
    final end = rain.rainEndsAt;
    if (end == null) return '';
    if (rain.segments.length == 1 &&
        rain.segments.first.intensity == RainIntensity.possible) {
      return ' Có thể có mưa rải rác đến khoảng ${_clock(end)}.';
    }
    final dur = rain.durationMinutes;
    final durText = dur != null ? ' (~$dur phút)' : '';
    return ' Dự kiến kéo dài đến khoảng ${_clock(end)}$durText.';
  }

  WeatherAlert _rainStopAlert(RainStatus rain, DateTime ref) => WeatherAlert(
        id: NotificationIds.rainStop,
        title: 'Mưa sắp tạnh',
        body: '${KatoVoice.rainStopping(ref.minute)}'
            'Mưa dự kiến tạnh ${_timingPhrase(rain, ref)}. '
            'Đường vẫn còn ướt, hãy di chuyển cẩn thận.',
      );

  /// Pha rainStartingSoon/rainStoppingSoon giữ nguyên nhưng thời điểm dự kiến
  /// lệch đủ lớn so với lần ĐÃ BÁO → cần báo lại. Ngưỡng bất đối xứng: mưa đến
  /// SỚM hơn quan trọng hơn (người dùng có thể ra đường trễ) nên ngưỡng thấp;
  /// mưa DỜI MUỘN dùng ngưỡng cao để dự báo "trôi" dần không gây spam.
  bool _shouldRenotifyTimeShift(RainStatus rain, DateTime? previousChangeAt) {
    if (rain.phase != RainPhase.rainStartingSoon &&
        rain.phase != RainPhase.rainStoppingSoon) {
      return false;
    }
    final at = rain.changeAt;
    if (at == null || previousChangeAt == null) return false;
    final shiftMinutes = at.difference(previousChangeAt).inMinutes;
    return shiftMinutes <= -AppConfig.rainTimeShiftRenotifyMinutes ||
        shiftMinutes >= AppConfig.rainTimeShiftLaterRenotifyMinutes;
  }

  /// Đã cảnh báo "sắp mưa" khi cơn mưa còn XA (lệch báo > ngưỡng nhắc), nay
  /// onset áp sát còn ≤ `rainReminderLeadMinutes` → nhắc lại MỘT lần. Sau khi
  /// nhắc, `notifiedAt` được chốt lại gần onset nên điều kiện không thoả nữa
  /// (không lặp).
  bool _shouldRemindOnsetClose(
    RainStatus rain,
    DateTime? previousChangeAt,
    DateTime? previousNotifiedAt,
    DateTime ref,
  ) {
    if (rain.phase != RainPhase.rainStartingSoon) return false;
    final at = rain.changeAt;
    if (at == null || previousNotifiedAt == null) return false;
    final lead = at.difference(ref).inMinutes;
    if (lead <= 0 || lead > AppConfig.rainReminderLeadMinutes) return false;
    final notifiedLead = (previousChangeAt ?? at)
        .difference(previousNotifiedAt)
        .inMinutes;
    return notifiedLead > AppConfig.rainReminderLeadMinutes;
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

  /// Thời điểm chuyển biến ĐÃ BÁO (giữ nguyên giá trị cũ nếu lần này không
  /// phát thông báo mưa) — lưu lại để lần sau so lệch giờ (báo "Cập nhật").
  final DateTime? newChangeAt;

  /// Thời điểm PHÁT thông báo mưa gần nhất (giữ giá trị cũ nếu lần này không
  /// phát) — dùng để biết lần báo trước cách onset bao xa (nhắc lại khi áp sát).
  final DateTime? newNotifiedAt;
  final bool envNotified;
  const AlertResult({
    required this.alerts,
    required this.newPhase,
    required this.newCategory,
    this.newChangeAt,
    this.newNotifiedAt,
    required this.envNotified,
  });
}
