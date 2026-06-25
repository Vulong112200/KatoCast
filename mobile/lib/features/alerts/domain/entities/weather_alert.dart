/// Một thông báo cần hiển thị (mapping sang NotificationService).
class WeatherAlert {
  final int id; // dùng NotificationIds để cố định theo loại
  final String title;
  final String body;
  const WeatherAlert({required this.id, required this.title, required this.body});
}
