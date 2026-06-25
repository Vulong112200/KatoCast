import 'hourly.dart';
import 'minutely.dart';

/// Thời tiết hiện tại — entity domain thuần (đơn vị đã chuẩn hoá metric).
class CurrentWeather {
  final DateTime time;
  final double tempC;
  final double feelsLikeC;
  final int humidity; // %
  final double uvi; // chỉ số UV
  final int clouds; // %
  final double windSpeed; // m/s

  /// Mã điều kiện thời tiết OpenWeatherMap (weather[0].id) — dùng để phân loại
  /// nắng / mây / mưa nhỏ-to / dông-bão. Xem `WeatherCondition.classify`.
  final int conditionId;
  final String description;
  final String icon;

  /// Lượng mưa 1h gần nhất (mm), 0 nếu không mưa.
  final double rain1h;

  const CurrentWeather({
    required this.time,
    required this.tempC,
    required this.feelsLikeC,
    required this.humidity,
    required this.uvi,
    required this.clouds,
    required this.windSpeed,
    required this.conditionId,
    required this.description,
    required this.icon,
    required this.rain1h,
  });
}

/// Tổng hợp dữ liệu thời tiết cho 1 toạ độ (kết quả One Call 3.0).
class WeatherData {
  final CurrentWeather current;

  /// Dự báo từng phút trong 60 phút tới (có thể rỗng nếu API/khu vực không có).
  final List<MinutelyForecast> minutely;

  /// Dự báo từng giờ (tối đa 48h).
  final List<HourlyForecast> hourly;

  /// Thời điểm dữ liệu được lấy (dùng hiển thị "cập nhật lúc ..." khi offline).
  final DateTime fetchedAt;

  const WeatherData({
    required this.current,
    required this.minutely,
    required this.hourly,
    required this.fetchedAt,
  });
}
