/// Dự báo lượng mưa theo từng phút/mốc ngắn (One Call `minutely`, hoặc nowcast
/// 15' của 4.0 đã chuẩn hoá).
class MinutelyForecast {
  final DateTime time;

  /// Lượng mưa dự báo (mm/h) tại mốc này.
  final double precipitationMmH;

  /// Xác suất mưa 0..1 tại mốc này (nowcast 15' của 4.0 có sẵn; 0 nếu thiếu).
  /// Nowcast NHẠY hơn hourly.pop với mưa sắp tới → dùng cho cột giờ gần.
  final double pop;

  const MinutelyForecast({
    required this.time,
    required this.precipitationMmH,
    this.pop = 0,
  });
}
