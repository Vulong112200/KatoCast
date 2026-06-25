import '../../../../core/config/app_config.dart';
import '../entities/hourly.dart';
import '../entities/minutely.dart';
import '../entities/rain_status.dart';
import '../entities/weather.dart';

/// Use case CỐT LÕI: phân tích khi nào bắt đầu/kết thúc mưa.
///
/// Ưu tiên `minutely` (chính xác từng phút trong 60'). Nếu không có thì fallback
/// sang `hourly` (xác suất + lượng mưa). Logic tách riêng & thuần (không phụ
/// thuộc Flutter) để dễ unit-test các ca biên.
class AnalyzeRain {
  const AnalyzeRain();

  static const double _threshold = AppConfig.rainThresholdMmH;
  static const int _dryStreak = AppConfig.dryStreakToConfirmStop;

  RainStatus call(WeatherData data) {
    if (data.minutely.isNotEmpty) {
      return _fromMinutely(data.minutely);
    }
    return _fromHourly(data.hourly);
  }

  // --- Phân tích theo chuỗi dự báo ngắn hạn ---
  //
  // Độc lập với độ phân giải: dùng MỐC THỜI GIAN (time) để tính số phút, nên
  // chạy đúng cho cả `minutely` 1 phút (One Call 3.0) lẫn nowcast 15 phút
  // (One Call 4.0 — đã chuẩn hoá về cùng entity ở data layer).
  RainStatus _fromMinutely(List<MinutelyForecast> minutely) {
    final rainingNow = minutely.first.precipitationMmH > _threshold;

    if (!rainingNow) {
      // Đang khô → tìm mốc đầu tiên có mưa.
      for (var i = 0; i < minutely.length; i++) {
        if (minutely[i].precipitationMmH > _threshold) {
          return RainStatus(
            phase: RainPhase.rainStartingSoon,
            minutesUntilChange: _minutesAt(minutely, i),
            fromMinutely: true,
          );
        }
      }
      return const RainStatus.dry();
    }

    // Đang mưa → tìm mốc bắt đầu "khô bền vững" (>= _dryStreak mốc khô liên tiếp)
    // để tránh báo tạnh sai do 1 mốc lặng giữa cơn mưa.
    for (var i = 1; i < minutely.length; i++) {
      if (minutely[i].precipitationMmH <= _threshold) {
        if (_isDrySustained(minutely, i)) {
          return RainStatus(
            phase: RainPhase.rainStoppingSoon,
            minutesUntilChange: _minutesAt(minutely, i),
            fromMinutely: true,
          );
        }
      }
    }
    return const RainStatus.raining();
  }

  /// Số phút từ mốc đầu tiên tới mốc [i] (>= 0). Fallback về index nếu thiếu time.
  int _minutesAt(List<MinutelyForecast> minutely, int i) {
    final diff = minutely[i].time.difference(minutely.first.time).inMinutes;
    return diff >= 0 ? diff : i;
  }

  /// Từ phút [start], kiểm tra có đủ chuỗi khô liên tiếp không (xét tới hết
  /// cửa sổ nếu dữ liệu ngắn hơn _dryStreak).
  bool _isDrySustained(List<MinutelyForecast> minutely, int start) {
    final end = (start + _dryStreak).clamp(0, minutely.length);
    for (var j = start; j < end; j++) {
      if (minutely[j].precipitationMmH > _threshold) return false;
    }
    return true;
  }

  // --- Fallback theo giờ ---
  RainStatus _fromHourly(List<HourlyForecast> hourly) {
    if (hourly.isEmpty) return const RainStatus.dry(fromMinutely: false);

    bool isWet(HourlyForecast h) =>
        h.rainMm > _threshold || h.pop >= 0.5;

    final rainingNow = isWet(hourly.first);

    if (!rainingNow) {
      for (var i = 0; i < hourly.length; i++) {
        if (isWet(hourly[i])) {
          return RainStatus(
            phase: RainPhase.rainStartingSoon,
            minutesUntilChange: i * 60,
            fromMinutely: false,
          );
        }
      }
      return const RainStatus.dry(fromMinutely: false);
    }

    for (var i = 1; i < hourly.length; i++) {
      if (!isWet(hourly[i])) {
        return RainStatus(
          phase: RainPhase.rainStoppingSoon,
          minutesUntilChange: i * 60,
          fromMinutely: false,
        );
      }
    }
    return const RainStatus.raining(fromMinutely: false);
  }
}
