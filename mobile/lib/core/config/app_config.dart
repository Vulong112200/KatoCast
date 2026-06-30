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

  /// Tầm nhìn (phút) coi là "sắp mưa". Onset xa hơn ngưỡng này (chỉ xảy ra ở
  /// fallback hourly) không báo "sắp mưa" để tránh cảnh báo quá sớm/không sát.
  static const int rainSoonHorizonMinutes = 120;

  /// Khoảng cách (mét) di chuyển tối thiểu để cập nhật lại vị trí (tối ưu pin).
  static const int locationDistanceFilterMeters = 200;

  /// Chu kỳ background check thời tiết (phút). Android tối thiểu ~15 phút.
  static const int backgroundIntervalMinutes = 15;

  /// Ngưỡng thay đổi nhiệt độ mạnh giữa hiện tại và vài giờ tới (°C).
  static const double strongTempDeltaC = 5.0;

  /// Ngưỡng thay đổi độ ẩm mạnh (%).
  static const double strongHumidityDeltaPct = 20.0;

  /// Thời gian cache thời tiết còn coi là "tươi" (phút) — dùng cho badge "dữ
  /// liệu cũ" trên UI.
  static const int cacheFreshnessMinutes = 30;

  /// Ngưỡng tuổi cache để mở app TỰ gọi API làm mới (phút). Khớp chu kỳ nền
  /// 15' → mở app khi cache còn trong ngưỡng này sẽ hiển thị ngay, không tốn
  /// thêm lượt gọi API.
  static const int weatherRevalidateMinutes = 15;

  /// Cache thời tiết cũ hơn ngưỡng này (ngày) sẽ bị dọn để DB không phình.
  static const int cacheMaxAgeDays = 7;

  /// Vị trí "last known" cũ hơn ngưỡng này (giờ) coi là không đáng tin ở
  /// background → bỏ qua lần check để tránh cảnh báo nhầm khu vực.
  static const int backgroundLastKnownMaxAgeHours = 3;

  // --- Bản tin thời tiết hằng ngày ---

  /// Mốc giờ bản tin buổi sáng mặc định (phút-trong-ngày). 390 = 6:30.
  static const int digestDefaultMorningMinutes = 6 * 60 + 30;

  /// Mốc giờ bản tin buổi chiều mặc định (phút-trong-ngày). 990 = 16:30.
  static const int digestDefaultEveningMinutes = 16 * 60 + 30;

  /// Ngưỡng chỉ số UV để nhắc chống nắng trong bản tin.
  static const double digestUvWarnThreshold = 6.0;

  // --- Định danh & endpoint dịch vụ ngoài ---

  /// User-Agent định danh app (chính sách OSM/Overpass yêu cầu UA rõ ràng;
  /// thiếu UA dễ bị chặn/giới hạn tốc độ). Dùng chung cho Overpass/tile/RSS.
  static const String userAgent = 'KatoCast/1.0 (co.allexceed.katocast)';

  /// Package name cho `userAgentPackageName` của flutter_map TileLayer.
  static const String tilePackageName = 'co.allexceed.katocast';

  /// Các mirror Overpass (OpenStreetMap) — thử lần lượt để chịu lỗi khi 1
  /// endpoint quá tải/timeout/429. Tất cả miễn phí, không cần API key.
  static const List<String> overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://overpass.openstreetmap.fr/api/interpreter',
  ];

  /// Tile bản đồ nền OpenStreetMap.
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Lớp phủ lượng mưa OpenWeatherMap (cần `owmApiKey`).
  static String get owmPrecipTileUrl =>
      'https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png'
      '?appid=$owmApiKey';

  /// RSS tin thời tiết (VnExpress) — không cần key.
  static const String rssWeatherFeedUrl =
      'https://vnexpress.net/rss/thoi-tiet.rss';

  static bool get hasApiKey => owmApiKey.isNotEmpty;
}
