import 'hourly.dart';
import 'minutely.dart';

/// Thời tiết hiện tại — entity domain thuần (đơn vị đã chuẩn hoá metric).
///
/// Các trường số dùng kiểu nullable: `null` = API KHÔNG trả trường đó (dữ liệu
/// thiếu) để UI hiển thị "—" thay vì "0" gây hiểu nhầm. Chỉ [rain1h] mặc định 0
/// vì "vắng lượng mưa" nghĩa là không mưa.
class CurrentWeather {
  final DateTime time;
  final double? tempC;
  final double? feelsLikeC;
  final int? humidity; // %
  final double? uvi; // chỉ số UV
  final int? clouds; // %
  final double? windSpeed; // m/s

  /// Hướng gió (độ, 0–360), null nếu thiếu.
  final int? windDeg;

  /// Gió giật (m/s), null nếu thiếu.
  final double? windGust;

  /// Áp suất khí quyển (hPa), null nếu thiếu.
  final int? pressure;

  /// Điểm sương (°C), null nếu thiếu.
  final double? dewPointC;

  /// Tầm nhìn (mét), null nếu thiếu.
  final int? visibilityM;

  /// Mã điều kiện thời tiết OpenWeatherMap (weather[0].id) — dùng để phân loại
  /// nắng / mây / mưa nhỏ-to / dông-bão. Xem `WeatherCondition.classify`.
  /// null nếu API thiếu `weather[]` (→ phân loại "không rõ", KHÔNG mặc định nắng).
  final int? conditionId;
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
    this.windDeg,
    this.windGust,
    this.pressure,
    this.dewPointC,
    this.visibilityM,
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

  /// `true` khi dữ liệu này là CACHE CŨ trả về do fetch remote thất bại
  /// (offline/Doze/lỗi server), KHÔNG phải lần gọi API tươi. Dùng để caller
  /// (foreground notif, alarm backstop) biết dữ liệu chưa được làm mới thật sự
  /// và báo trung thực "dữ liệu cũ" thay vì hiển thị `fetchedAt` như thể mới.
  final bool fromCacheFallback;

  const WeatherData({
    required this.current,
    required this.minutely,
    required this.hourly,
    required this.fetchedAt,
    this.fromCacheFallback = false,
  });
}
