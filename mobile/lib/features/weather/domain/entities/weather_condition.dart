/// Phân loại tình hình thời tiết từ mã điều kiện OpenWeatherMap (weather[0].id).
///
/// Bảng mã: https://openweathermap.org/weather-conditions
/// - 2xx: dông/giông (thunderstorm)
/// - 3xx: mưa phùn (drizzle)
/// - 5xx: mưa (rain) — chia theo cường độ
/// - 6xx: tuyết (snow)
/// - 7xx: khí quyển (sương mù, bụi, lốc 781)
/// - 800: trời quang/nắng
/// - 80x: mây
///
/// Mỗi nhóm gắn nhãn tiếng Việt + lời khuyên + mức độ nghiêm trọng để vừa hiển
/// thị trên UI, vừa quyết định có đẩy thông báo cảnh báo hay không.
enum WeatherCategory {
  clear, // trời nắng/quang
  fewClouds, // ít/vài mây
  cloudy, // nhiều mây
  overcast, // u ám
  fog, // sương mù / tầm nhìn kém
  drizzle, // mưa phùn
  lightRain, // mưa nhỏ
  moderateRain, // mưa vừa
  heavyRain, // mưa to
  thunderstorm, // dông/giông
  severeStorm, // bão lớn / dông mạnh / lốc xoáy
  snow, // tuyết
  other,
}

/// Mức độ nghiêm trọng — dùng để gate notification & màu sắc UI.
enum WeatherSeverity { info, notice, warning, severe }

class WeatherCondition {
  final WeatherCategory category;
  final WeatherSeverity severity;

  /// Nhãn hiển thị tiếng Việt (vd "Mưa to", "Bão lớn").
  final String label;

  /// Lời khuyên cá nhân hóa.
  final String advice;

  /// Emoji minh hoạ (dùng cho thông báo/UI nhẹ).
  final String emoji;

  const WeatherCondition({
    required this.category,
    required this.severity,
    required this.label,
    required this.advice,
    required this.emoji,
  });

  // --- Mã điều kiện OpenWeatherMap (https://openweathermap.org/weather-conditions) ---

  /// Dông mạnh: dông kèm mưa to/rất to (211 nặng hạt, 212 dữ dội, 221 thất thường).
  static const Set<int> kSevereThunderstormIds = {211, 212, 221};

  /// Mưa cực to: 503 (rất nặng hạt), 504 (cực lớn), 522/531 (mưa rào dữ dội/thất thường).
  static const Set<int> kExtremeRainIds = {503, 504, 522, 531};

  /// Mưa to: 502 (nặng hạt), 521 (mưa rào nặng).
  static const Set<int> kHeavyRainIds = {502, 521};

  /// Mã lốc xoáy (nhóm 7xx khí quyển).
  static const int kTornadoId = 781;

  /// Ngưỡng lượng mưa (mm/h) nâng cấp cường độ.
  static const double kRainMmHSevere = 7.6; // rất to
  static const double kRainMmHHeavy = 2.5; // to

  /// Phân loại từ mã điều kiện. [rainMmH] (nếu có) giúp tinh chỉnh cường độ mưa.
  /// [conditionId] null (API thiếu `weather[]`) → "Không rõ tình hình" thay vì
  /// mặc định nắng — tránh cung cấp thông tin sai.
  factory WeatherCondition.classify(int? conditionId, {double rainMmH = 0}) {
    if (conditionId == null) {
      return const WeatherCondition(
        category: WeatherCategory.other,
        severity: WeatherSeverity.info,
        label: 'Không rõ tình hình',
        advice: '',
        emoji: '🌡️',
      );
    }
    // --- 2xx: Dông/giông ---
    if (conditionId >= 200 && conditionId < 300) {
      // Dông mạnh hoặc kèm mưa lớn → bão lớn.
      if (kSevereThunderstormIds.contains(conditionId) ||
          rainMmH >= kRainMmHSevere) {
        return const WeatherCondition(
          category: WeatherCategory.severeStorm,
          severity: WeatherSeverity.severe,
          label: 'Bão lớn / dông mạnh',
          advice: 'Thời tiết nguy hiểm. Hạn chế ra ngoài, tránh xa cây lớn, '
              'biển hiệu và thiết bị điện ngoài trời.',
          emoji: '⛈️',
        );
      }
      return const WeatherCondition(
        category: WeatherCategory.thunderstorm,
        severity: WeatherSeverity.severe,
        label: 'Dông / giông',
        advice: 'Có dông sét. Hãy vào nơi trú an toàn và tránh khu vực trống trải.',
        emoji: '🌩️',
      );
    }

    // --- 3xx: Mưa phùn ---
    if (conditionId >= 300 && conditionId < 400) {
      return const WeatherCondition(
        category: WeatherCategory.drizzle,
        severity: WeatherSeverity.notice,
        label: 'Mưa phùn',
        advice: 'Trời lất phất mưa, đường có thể trơn nhẹ. Mang theo áo khoác mỏng.',
        emoji: '🌦️',
      );
    }

    // --- 5xx: Mưa (chia cường độ) ---
    if (conditionId >= 500 && conditionId < 600) {
      // Cực to: 503, 504, 522, 531 hoặc lượng mưa rất lớn.
      if (kExtremeRainIds.contains(conditionId) || rainMmH >= kRainMmHSevere) {
        return const WeatherCondition(
          category: WeatherCategory.heavyRain,
          severity: WeatherSeverity.severe,
          label: 'Mưa rất to',
          advice: 'Mưa rất lớn, nguy cơ ngập và tầm nhìn kém. Hạn chế di chuyển; '
              'nếu phải đi, chú ý đường ngập và trơn trượt.',
          emoji: '🌧️',
        );
      }
      // To: 502, 521.
      if (kHeavyRainIds.contains(conditionId) || rainMmH >= kRainMmHHeavy) {
        return const WeatherCondition(
          category: WeatherCategory.heavyRain,
          severity: WeatherSeverity.warning,
          label: 'Mưa to',
          advice: 'Mưa to. Mang áo mưa, đề phòng đường ngập và trơn trượt.',
          emoji: '🌧️',
        );
      }
      // Vừa: 501.
      if (conditionId == 501) {
        return const WeatherCondition(
          category: WeatherCategory.moderateRain,
          severity: WeatherSeverity.notice,
          label: 'Mưa vừa',
          advice: 'Mưa vừa. Nên mang theo ô hoặc áo mưa.',
          emoji: '🌧️',
        );
      }
      // Nhỏ: 500, 520 và còn lại.
      return const WeatherCondition(
        category: WeatherCategory.lightRain,
        severity: WeatherSeverity.notice,
        label: 'Mưa nhỏ',
        advice: 'Có mưa nhỏ. Mang theo ô cho chắc chắn.',
        emoji: '🌦️',
      );
    }

    // --- 6xx: Tuyết ---
    if (conditionId >= 600 && conditionId < 700) {
      return const WeatherCondition(
        category: WeatherCategory.snow,
        severity: WeatherSeverity.warning,
        label: 'Tuyết',
        advice: 'Có tuyết, đường trơn. Giữ ấm và di chuyển cẩn thận.',
        emoji: '🌨️',
      );
    }

    // --- 7xx: Khí quyển (sương mù, bụi, lốc xoáy) ---
    if (conditionId >= 700 && conditionId < 800) {
      if (conditionId == kTornadoId) {
        return const WeatherCondition(
          category: WeatherCategory.severeStorm,
          severity: WeatherSeverity.severe,
          label: 'Lốc xoáy',
          advice: 'Cực kỳ nguy hiểm! Tìm nơi trú ẩn kiên cố ngay lập tức.',
          emoji: '🌪️',
        );
      }
      return const WeatherCondition(
        category: WeatherCategory.fog,
        severity: WeatherSeverity.notice,
        label: 'Sương mù / tầm nhìn kém',
        advice: 'Tầm nhìn hạn chế. Lái xe chậm và bật đèn nếu cần.',
        emoji: '🌫️',
      );
    }

    // --- 800: Trời quang/nắng ---
    if (conditionId == 800) {
      return const WeatherCondition(
        category: WeatherCategory.clear,
        severity: WeatherSeverity.info,
        label: 'Trời nắng / quang đãng',
        advice: 'Trời đẹp. Nếu chỉ số UV cao, nhớ chống nắng khi ra ngoài.',
        emoji: '☀️',
      );
    }

    // --- 80x: Mây ---
    if (conditionId == 801 || conditionId == 802) {
      return const WeatherCondition(
        category: WeatherCategory.fewClouds,
        severity: WeatherSeverity.info,
        label: 'Ít mây',
        advice: 'Trời có vài đám mây, thời tiết dễ chịu.',
        emoji: '🌤️',
      );
    }
    if (conditionId == 803) {
      return const WeatherCondition(
        category: WeatherCategory.cloudy,
        severity: WeatherSeverity.info,
        label: 'Nhiều mây',
        advice: 'Trời nhiều mây.',
        emoji: '⛅',
      );
    }
    if (conditionId == 804) {
      return const WeatherCondition(
        category: WeatherCategory.overcast,
        severity: WeatherSeverity.info,
        label: 'Trời u ám',
        advice: 'Mây phủ kín trời, có thể chuyển mưa.',
        emoji: '☁️',
      );
    }

    return const WeatherCondition(
      category: WeatherCategory.other,
      severity: WeatherSeverity.info,
      label: 'Thời tiết',
      advice: '',
      emoji: '🌡️',
    );
  }
}
