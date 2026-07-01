import '../../../../core/config/app_config.dart';
import '../../../weather/domain/entities/rain_status.dart';
import '../../../weather/domain/entities/weather.dart';
import '../../../weather/domain/entities/weather_condition.dart';
import '../../../weather/domain/usecases/analyze_rain.dart';
import '../../../weather/domain/usecases/build_rain_outlook.dart';

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

    // Tổng quan mưa CẢ NGÀY theo buổi (trả lời "hôm nay có mưa không, mấy giờ").
    final outlook = const BuildRainOutlook().call(data);
    if (outlook != null) parts.add(outlook);

    // Gợi ý mưa TỨC THỜI (đang/sắp mưa trong ~2h tới) — bổ sung cho outlook.
    final rain = const AnalyzeRain().call(data);
    final rainHint = _rainHint(rain);
    if (rainHint != null) parts.add(rainHint);

    // Nhắc chống nắng khi UV cao.
    if (c.uvi >= AppConfig.digestUvWarnThreshold) {
      parts.add('Chỉ số UV cao (${c.uvi.round()}) — nhớ chống nắng khi ra ngoài.');
    }

    // Mốc thời gian dữ liệu được lấy — cho người dùng biết độ tươi của bản tin.
    parts.add('Cập nhật lúc ${_clock(data.fetchedAt)}.');

    return DailyDigest(title: title, body: parts.join(' '));
  }

  String? _rainHint(RainStatus rain) {
    final pct = rain.probabilityPct;
    final chance = pct != null ? ' (khả năng ~$pct%)' : '';
    switch (rain.phase) {
      case RainPhase.rainStartingSoon:
        final n = rain.minutesUntilChange;
        return n != null
            ? 'Dự kiến mưa lúc ${_clockAfter(n)} (khoảng $n phút tới)$chance.'
            : 'Sắp có mưa$chance.';
      case RainPhase.raining:
        return 'Hiện đang có mưa$chance.';
      case RainPhase.rainStoppingSoon:
        final n = rain.minutesUntilChange;
        return n != null
            ? 'Mưa dự kiến tạnh lúc ${_clockAfter(n)} (khoảng $n phút tới).'
            : 'Mưa sắp tạnh.';
      case RainPhase.dry:
        return null;
    }
  }

  /// HH:MM của một thời điểm.
  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// HH:MM sau [minutes] phút kể từ bây giờ.
  String _clockAfter(int minutes) =>
      _clock(DateTime.now().add(Duration(minutes: minutes)));
}
