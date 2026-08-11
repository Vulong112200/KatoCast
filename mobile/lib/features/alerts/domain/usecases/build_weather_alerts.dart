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
    double observedRain1hMm = 0,
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
            alerts.add(
              WeatherAlert(
                id: NotificationIds.rainStop,
                title: 'Trời đã tạnh mưa',
                body:
                    '${KatoVoice.cleared(ref.minute)}'
                    'Trời đã tạnh mưa tại khu vực của bạn, đường vẫn còn ướt, '
                    'hãy di chuyển cẩn thận.',
              ),
            );
            rainAlertFired = true;
          }
        case RainPhase.raining:
          if (!_wasRaining(previousPhase)) {
            alerts.add(
              WeatherAlert(
                id: NotificationIds.rainStart,
                title: 'Trời đang mưa',
                body:
                    '${KatoVoice.raining(ref.minute)}'
                    'Hiện đang có mưa tại vị trí của bạn.'
                    '${_chanceSuffix(rain.probabilityPct, raining: true)} '
                    'Hãy chuẩn bị áo mưa và chú ý đường trơn trượt.',
              ),
            );
            rainAlertFired = true;
          }
      }
    } else if (_shouldRenotifyTimeShift(rain, previousChangeAt)) {
      // Pha giữ nguyên nhưng thời điểm dự kiến lệch đáng kể → báo cập nhật.
      final updated = rain.phase == RainPhase.rainStartingSoon
          ? _rainStartAlert(rain, ref)
          : _rainStopAlert(rain, ref);
      alerts.add(
        WeatherAlert(
          id: updated.id,
          title: 'Cập nhật: ${updated.title}',
          body: updated.body,
        ),
      );
      rainAlertFired = true;
    } else if (_shouldRemindOnsetClose(
      rain,
      previousChangeAt,
      previousNotifiedAt,
      ref,
    )) {
      // Đã báo từ xa, cơn mưa nay áp sát → nhắc lại một lần (cùng ID).
      final base = _rainStartAlert(rain, ref);
      alerts.add(
        WeatherAlert(
          id: base.id,
          // `còn khoảng 0 phút` đọc rất vô nghĩa — cơn mưa tới nơi rồi thì nói thẳng.
          title: (rain.minutesUntilChange ?? 0) <= 1
              ? 'Sắp mưa: ngay bây giờ'
              : 'Sắp mưa: còn khoảng ${rain.minutesUntilChange} phút',
          body: base.body,
        ),
      );
      rainAlertFired = true;
    }

    // --- 2. Tình hình thời tiết (nắng/mây/mưa/bão) — chỉ khi nhóm đổi ---
    //
    // KHỞI ĐẦU MỚI (`previousCategory == null`: lần chạy đầu, hoặc trạng thái cũ
    // đã hết hạn vì app bị ngắt hàng giờ) thì "nhóm đổi" là đương nhiên đúng —
    // nhưng nó KHÔNG phải một sự kiện thời tiết. Nhật ký thật cho thấy hậu quả:
    // mỗi lần app hồi sinh sau một khoảng đứt, người dùng nhận ngay một thông
    // báo vô ích ("🌤️ Nhiều mây — Trời nhiều mây.", "☁️ Trời u ám") — 02/08
    // 06:50, 04/08 12:33, và đó là phần lớn trong "4 thông báo/24h". Nên ở lần
    // khởi đầu, chỉ báo khi tình hình THỰC SỰ đáng biết.
    // Mã mưa NHẸ/VỪA của OWM cần được xác nhận trước khi đem đi báo — xem
    // [_rainClaimUnsupported]. Không xác nhận được thì bỏ qua lượt này và GIỮ
    // `previousCategory` để lần sau (khi có bằng chứng) vẫn còn "nhóm đổi" mà báo.
    final suppressedReason = _rainClaimUnsupportedReason(
      condition,
      rain,
      observedRain1hMm,
    );
    final unsupportedRainClaim = suppressedReason != null;
    if (condition.category != previousCategory &&
        !unsupportedRainClaim &&
        (previousCategory != null || _worthAnnouncingOnFreshStart(condition))) {
      alerts.add(
        WeatherAlert(
          id: NotificationIds.condition,
          title: '${condition.emoji} ${condition.label}',
          body: condition.advice.isNotEmpty
              ? condition.advice
              : 'Tình hình thời tiết hiện tại: ${condition.label}.',
        ),
      );
    }

    // --- 3. Thay đổi môi trường mạnh — chỉ phát 1 lần cho tới khi hết mạnh ---
    if (env.hasStrongChange && !envAlreadyNotified) {
      alerts.add(
        WeatherAlert(
          id: NotificationIds.envChange,
          title: 'Thời tiết đang thay đổi mạnh',
          body:
              '${KatoVoice.envChange(ref.minute)}'
              'Độ ẩm/Nhiệt độ hiện tại đang thay đổi mạnh, '
              'chú ý không gian sống và thú cưng.',
        ),
      );
    }

    return AlertResult(
      alerts: alerts,
      newPhase: rain.phase,
      // Tình hình mưa CHƯA được xác nhận thì không chốt vào trạng thái: giữ nhóm
      // cũ để khi có bằng chứng thật, "nhóm đổi" vẫn còn hiệu lực và báo được.
      newCategory: unsupportedRainClaim
          ? (previousCategory ?? condition.category)
          : condition.category,
      // Chỉ chốt mốc mới khi pha đổi hoặc đã phát thông báo mưa; nếu không,
      // GIỮ mốc đã báo lần trước để lần sau còn so lệch được (chống drift).
      newChangeAt: (phaseChanged || rainAlertFired)
          ? rain.changeAt
          : previousChangeAt,
      newNotifiedAt: rainAlertFired ? ref : previousNotifiedAt,
      envNotified: env.hasStrongChange,
      suppressedReason: suppressedReason,
    );
  }

  WeatherAlert _rainStartAlert(RainStatus rain, DateTime ref) => WeatherAlert(
    id: NotificationIds.rainStart,
    title: 'Sắp mưa tại khu vực của bạn',
    body:
        '${KatoVoice.rainIncoming(ref.minute)}'
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
    body:
        '${KatoVoice.rainStopping(ref.minute)}'
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
    // ⚠️ `lead == 0` (mưa tới NGAY BÂY GIỜ) trước đây bị chặn — tức lời nhắc tự
    // tắt đúng vào khoảnh khắc nó có giá trị nhất. Chỉ loại mốc đã thuộc quá khứ.
    if (lead < 0 || lead > AppConfig.rainReminderLeadMinutes) return false;
    final notifiedLead = (previousChangeAt ?? at)
        .difference(previousNotifiedAt)
        .inMinutes;
    return notifiedLead > AppConfig.rainReminderLeadMinutes;
  }

  /// Ở lần KHỞI ĐẦU (chưa có trạng thái để so), tình hình này có đáng đánh thức
  /// người dùng không?
  ///
  /// Có: mưa/dông/bão/sương mù dày — thứ làm người ta đổi kế hoạch ra đường.
  /// Không: nắng, ít mây, nhiều mây, u ám — đó là "hôm nay trời như vậy", không
  /// phải tin. Dùng [WeatherSeverity] thay vì liệt kê nhóm để tự đúng khi thêm
  /// nhóm mới.
  /// Thông báo "tình hình" đang định nói là TRỜI MƯA, nhưng KHÔNG có gì chứng
  /// thực điều đó?
  ///
  /// ⚠️ Ca thật trong nhật ký 06/08/2026 09:38:22 — cùng một chu kỳ ghi:
  /// `pha: dry · tình hình: Mưa nhỏ · nowcast bây giờ: 0.00 mm/h · mưa 1h quan
  /// trắc: 0.16 mm · mã điều kiện OWM: 500`, rồi ngay sau đó
  /// `ĐÃ BÁO: 🌦️ Mưa nhỏ — "Có mưa nhỏ. Mang theo ô cho chắc chắn."`
  /// Tức app tự nói ngược với chính mình: phân tích mưa kết luận KHÔNG mưa, mà
  /// thông báo lại khẳng định đang có mưa — chỉ vì OWM gán mã 500 và 0.16 mm tích
  /// lũy của cả một giờ (mức gần như không cảm nhận được). `WeatherCondition`
  /// phân loại THUẦN theo mã điều kiện nên nó không biết chuyện đó.
  ///
  /// Điều kiện xác thực (chỉ cần MỘT trong hai) — cố ý dễ, để không bịt mất tin
  /// thật: phân tích mưa đồng ý là có mưa/sắp mưa, HOẶC **có lượng mưa đo được**
  /// (`observedRain1hMm > 0`).
  ///
  /// ⚠️ Ngưỡng cũ ở đây là [AppConfig.rainObsMm1hThreshold] (0.5 mm) và nó đã
  /// gây ra đúng sự việc 10/08/2026 18:03 — người dùng đi xe về giữa mưa nhẹ,
  /// nhật ký ghi `mã OWM 500 · mưa 1h quan trắc 0.10 mm` nhưng thông báo bị nuốt
  /// vì 0.10 < 0.5, và vì `newCategory` giữ nguyên nên các chu kỳ sau cũng không
  /// còn "nhóm đổi" để báo ⇒ app im lặng suốt quãng đường. Nhật ký hai ngày có
  /// **37 chu kỳ** mã 500 với lượng mưa 0.10–0.36 mm — tức toàn bộ dải mưa nhẹ
  /// THẬT nằm dưới ngưỡng 0.5. Lượng mưa đo được > 0 đã là bằng chứng vật lý;
  /// đòi thêm nữa là đòi hỏi sai chỗ.
  ///
  /// Chỉ áp cho nhóm mưa NHẸ/VỪA. Mưa to/dông/bão/lốc luôn được báo: sai một lần
  /// còn hơn im lặng trước thứ có thể gây nguy hiểm.
  ///
  /// Trả `null` khi cảnh báo hợp lệ; trả **lý do** khi bị chặn, để nơi gọi GHI
  /// NHẬT KÝ. Bản trước chặn trong im lặng nên nhật ký chỉ hiện dòng chung
  /// "KHÔNG báo — chưa có gì đổi", che mất nguyên nhân thật.
  String? _rainClaimUnsupportedReason(
    WeatherCondition condition,
    RainStatus rain,
    double observedRain1hMm,
  ) {
    final softRainCategory =
        condition.category == WeatherCategory.drizzle ||
        condition.category == WeatherCategory.lightRain ||
        condition.category == WeatherCategory.moderateRain;
    if (!softRainCategory) return null;
    if (rain.phase != RainPhase.dry) return null;
    if (observedRain1hMm > 0) return null;
    return 'nuốt cảnh báo "${condition.label}": phân tích mưa nói pha dry và '
        'không có lượng mưa đo được (mưa 1h quan trắc = 0.00 mm)';
  }

  bool _worthAnnouncingOnFreshStart(WeatherCondition condition) =>
      condition.severity == WeatherSeverity.notice ||
      condition.severity == WeatherSeverity.warning ||
      condition.severity == WeatherSeverity.severe;

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
    // ⚠️ "Khả năng mưa khoảng 0%" đứng ngay cạnh một cảnh báo MƯA là câu tự mâu
    // thuẫn — đã lên máy người dùng 11/08/2026 ("Dự kiến mưa lúc 18:30 … Khả
    // năng mưa khoảng 0%"). Nguồn gốc số 0 đã sửa ở `AnalyzeRain._probabilityPct`
    // (nay lấy MAX với pop nowcast), nhưng vẫn chặn ở đây: thà KHÔNG nói gì về
    // xác suất còn hơn nói một con số phủ định chính thông báo đang phát.
    if (pct <= 0) return '';
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

  /// Lý do một cảnh báo ĐÁNG LẼ phát đã bị chặn (null = không chặn gì).
  ///
  /// Tồn tại để nơi gọi GHI NHẬT KÝ. Trước đây việc chặn diễn ra âm thầm nên khi
  /// truy vụ 10/08/2026 (mưa nhẹ mà app im lặng) nhật ký chỉ có dòng chung
  /// "KHÔNG báo — chưa có gì đổi", phải đọc code mới biết cảnh báo bị nuốt ở đâu.
  final String? suppressedReason;

  const AlertResult({
    required this.alerts,
    required this.newPhase,
    required this.newCategory,
    this.newChangeAt,
    this.newNotifiedAt,
    required this.envNotified,
    this.suppressedReason,
  });
}
