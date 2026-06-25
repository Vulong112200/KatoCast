/// Dự báo lượng mưa theo từng phút (One Call 3.0 `minutely`).
class MinutelyForecast {
  final DateTime time;

  /// Lượng mưa dự báo (mm/h) tại phút này.
  final double precipitationMmH;

  const MinutelyForecast({
    required this.time,
    required this.precipitationMmH,
  });
}
