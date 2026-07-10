import '../../../../core/config/app_config.dart';
import '../entities/rain_status.dart';
import '../entities/uv_advice.dart';
import '../entities/weather.dart';
import '../entities/weather_condition.dart';

/// Loại ghi chú lưu ý — để UI chọn icon phù hợp.
enum AdvisoryKind { condition, uv, humidity, wind, rain }

/// Một dòng lưu ý dễ hiểu cho người dùng.
class Advisory {
  final AdvisoryKind kind;
  final String text;
  const Advisory(this.kind, this.text);
}

/// Use case gom nhiều lời khuyên/lưu ý dễ hiểu về thời tiết hiện tại thành
/// danh sách hiển thị trong app (thẻ "Lưu ý hôm nay").
///
/// Thuần (không phụ thuộc Flutter) để dễ test và tái dùng. Gộp: tình hình
/// (WeatherCondition), UV (UvAdvice), độ ẩm, gió, và mưa (RainStatus).
class BuildAdvisories {
  const BuildAdvisories();

  List<Advisory> call({
    required CurrentWeather current,
    required WeatherCondition condition,
    RainStatus? rain,
  }) {
    final items = <Advisory>[];

    // 1. Lời khuyên theo tình hình thời tiết (nắng/mây/mưa/bão).
    if (condition.advice.isNotEmpty) {
      items.add(Advisory(AdvisoryKind.condition, condition.advice));
    }

    // 2. UV theo mức (chỉ nhắc khi từ trung bình trở lên để tránh thừa).
    final uvi = current.uvi;
    if (uvi != null) {
      final uv = UvAdvice.classify(uvi);
      if (uv.needsProtection) {
        items.add(Advisory(
            AdvisoryKind.uv, 'UV ${uv.level} (${uv.label}): ${uv.advice}'));
      }
    }

    // 3. Độ ẩm.
    final humidity = current.humidity;
    if (humidity != null) {
      if (humidity >= AppConfig.humidityHighPct) {
        items.add(const Advisory(AdvisoryKind.humidity,
            'Độ ẩm cao, oi bức khó chịu — nhớ uống đủ nước.'));
      } else if (humidity <= AppConfig.humidityLowPct) {
        items.add(const Advisory(AdvisoryKind.humidity,
            'Không khí khô — dưỡng ẩm da và uống nước thường xuyên.'));
      }
    }

    // 4. Gió mạnh.
    final windSpeed = current.windSpeed;
    if (windSpeed != null && windSpeed >= AppConfig.strongWindMs) {
      items.add(Advisory(AdvisoryKind.wind,
          'Gió mạnh (${windSpeed.toStringAsFixed(0)} m/s), '
          'cẩn thận khi di chuyển ngoài trời.'));
    }

    // 5. Mưa sắp tới / đang mưa (bổ sung cho banner mưa).
    final rainText = _rainNote(rain);
    if (rainText != null) items.add(Advisory(AdvisoryKind.rain, rainText));

    return items;
  }

  String? _rainNote(RainStatus? rain) {
    if (rain == null) return null;
    final until = rain.rainEndsAt != null
        ? ' (dự kiến tạnh khoảng ${_clock(rain.rainEndsAt!)})'
        : '';
    switch (rain.phase) {
      case RainPhase.rainStartingSoon:
        final at = rain.changeAt;
        final pct = rain.probabilityPct;
        final chance = pct != null ? ', khả năng ~$pct%' : '';
        return at != null
            ? 'Sắp mưa lúc ${_clock(at)}$chance$until — mang theo áo mưa.'
            : 'Sắp có mưa — mang theo áo mưa.';
      case RainPhase.raining:
        return 'Hiện đang mưa — chú ý đường trơn trượt.';
      case RainPhase.rainStoppingSoon:
        final at = rain.changeAt;
        return at != null
            ? 'Mưa dự kiến tạnh khoảng ${_clock(at)}, đường có thể còn ướt.'
            : 'Mưa sắp tạnh, đường có thể còn ướt.';
      case RainPhase.dry:
        return null;
    }
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
