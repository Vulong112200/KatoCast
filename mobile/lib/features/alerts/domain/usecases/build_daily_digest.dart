import '../../../../core/config/app_config.dart';
import '../../../weather/domain/entities/rain_status.dart';
import '../../../weather/domain/entities/weather.dart';
import '../../../weather/domain/entities/weather_condition.dart';
import '../../../weather/domain/usecases/analyze_rain.dart';

/// Nội dung bản tin thời tiết hằng ngày (tiêu đề + thân thông báo).
class DailyDigest {
  final String title;
  final String body;

  const DailyDigest({required this.title, required this.body});
}

/// Use case CỐT LÕI: dựng bản tin tóm tắt thời tiết để gửi vào khung giờ cố
/// định (sáng/chiều). Thuần (không phụ thuộc Flutter) nên chạy được ở
/// background isolate; tái dùng `WeatherCondition.classify` + `AnalyzeRain`.
class BuildDailyDigest {
  const BuildDailyDigest();

  DailyDigest call(WeatherData data) {
    final c = data.current;
    final condition = WeatherCondition.classify(
      c.conditionId,
      rainMmH: c.rain1h,
    );

    // Tiêu đề: emoji + nhãn tình hình + nhiệt độ hiện tại.
    final title = '${condition.emoji} ${condition.label} · ${c.tempC.round()}°C';

    final parts = <String>[
      'Cảm giác như ${c.feelsLikeC.round()}°C, độ ẩm ${c.humidity}%.',
    ];

    // Hi/lo trong 24h tới (nếu có dữ liệu hourly).
    final next24 = data.hourly.take(24).toList();
    if (next24.isNotEmpty) {
      var lo = next24.first.tempC;
      var hi = next24.first.tempC;
      for (final h in next24) {
        if (h.tempC < lo) lo = h.tempC;
        if (h.tempC > hi) hi = h.tempC;
      }
      parts.add('Hôm nay khoảng ${lo.round()}–${hi.round()}°C.');
    }

    // Lời khuyên theo tình hình.
    if (condition.advice.isNotEmpty) {
      parts.add(condition.advice);
    }

    // Gợi ý mưa sắp tới (tái dùng AnalyzeRain).
    final rain = const AnalyzeRain().call(data);
    final rainHint = _rainHint(rain);
    if (rainHint != null) parts.add(rainHint);

    // Nhắc chống nắng khi UV cao.
    if (c.uvi >= AppConfig.digestUvWarnThreshold) {
      parts.add('Chỉ số UV cao (${c.uvi.round()}) — nhớ chống nắng khi ra ngoài.');
    }

    return DailyDigest(title: title, body: parts.join(' '));
  }

  String? _rainHint(RainStatus rain) {
    switch (rain.phase) {
      case RainPhase.rainStartingSoon:
        final n = rain.minutesUntilChange;
        return n != null
            ? 'Dự kiến có mưa trong khoảng $n phút tới.'
            : 'Sắp có mưa.';
      case RainPhase.raining:
        return 'Hiện đang có mưa.';
      case RainPhase.rainStoppingSoon:
        final n = rain.minutesUntilChange;
        return n != null
            ? 'Mưa dự kiến tạnh trong khoảng $n phút tới.'
            : 'Mưa sắp tạnh.';
      case RainPhase.dry:
        return null;
    }
  }
}
