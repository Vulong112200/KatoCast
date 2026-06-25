/// Cấu hình toàn cục của app.
///
/// API key được nạp qua `--dart-define` để KHÔNG hardcode khoá vào source.
/// Chạy: `flutter run --dart-define=OWM_API_KEY=xxxxx`
/// (hoặc `--dart-define-from-file=env.json`).
///
/// Đây thuộc tầng "infrastructure config" — các tham số tinh chỉnh
/// (ngưỡng mưa, khoảng cách cập nhật vị trí, chu kỳ background) gom về một chỗ
/// để dễ thay đổi mà không phải đụng vào business logic.
class AppConfig {
  const AppConfig._();

  /// Khoá API OpenWeatherMap (One Call 3.0). Rỗng nếu chưa cấu hình.
  static const String owmApiKey = String.fromEnvironment('OWM_API_KEY');

  /// Phiên bản One Call API đang dùng. App target **4.0**.
  ///
  /// 4.0 tách thành nhiều endpoint timeline; `WeatherRemoteDataSource` gọi
  /// `/onecall/current` + `/onecall/timeline/15min` + `/onecall/timeline/1h`
  /// rồi chuẩn hoá về shape gộp (current + minutely + hourly) cho `WeatherMapper`.
  /// Lưu ý: mỗi lần refresh = 3 lượt gọi API (cân nhắc hạn mức 1000 calls/ngày).
  static const String owmApiVersion = '4.0';

  /// Base URL One Call API.
  static const String owmBaseUrl =
      'https://api.openweathermap.org/data/$owmApiVersion';

  /// Đơn vị đo: metric => °C, m/s.
  static const String owmUnits = 'metric';

  /// Ngôn ngữ mô tả thời tiết trả về.
  static const String owmLang = 'vi';

  /// Ngưỡng coi là "có mưa" (mm/h). Dưới ngưỡng coi như khô (lọc nhiễu).
  static const double rainThresholdMmH = 0.1;

  /// Số phút khô liên tiếp cần xác nhận để coi là "đã tạnh" (chống nhiễu 1 phút).
  static const int dryStreakToConfirmStop = 3;

  /// Khoảng cách (mét) di chuyển tối thiểu để cập nhật lại vị trí (tối ưu pin).
  static const int locationDistanceFilterMeters = 200;

  /// Chu kỳ background check thời tiết (phút). Android tối thiểu ~15 phút.
  static const int backgroundIntervalMinutes = 15;

  /// Ngưỡng thay đổi nhiệt độ mạnh giữa hiện tại và vài giờ tới (°C).
  static const double strongTempDeltaC = 5.0;

  /// Ngưỡng thay đổi độ ẩm mạnh (%).
  static const double strongHumidityDeltaPct = 20.0;

  /// Thời gian cache thời tiết còn coi là "tươi" (phút).
  static const int cacheFreshnessMinutes = 30;

  static bool get hasApiKey => owmApiKey.isNotEmpty;
}
