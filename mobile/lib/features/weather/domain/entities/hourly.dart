/// Dự báo theo giờ (One Call 3.0 `hourly`).
class HourlyForecast {
  final DateTime time;
  final double tempC;
  final int humidity; // %

  /// Xác suất mưa 0..1.
  final double pop;

  /// Lượng mưa dự báo (mm) trong giờ đó, 0 nếu không.
  final double rainMm;
  final String description;
  final String icon;

  const HourlyForecast({
    required this.time,
    required this.tempC,
    required this.humidity,
    required this.pop,
    required this.rainMm,
    required this.description,
    required this.icon,
  });
}
