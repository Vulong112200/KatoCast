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

  /// Ngưỡng xác suất mưa (pop 0..1) để một GIỜ được coi là "ướt" ở fallback
  /// hourly của AnalyzeRain (cảnh báo tức thời). Cao hơn ngưỡng outlook (0.4)
  /// vì cảnh báo tức thời cần chắc chắn hơn để tránh báo nhầm.
  static const double rainAlertPopThreshold = 0.5;

  /// Độ lệch (phút) khi mưa đến SỚM hơn thời điểm ĐÃ BÁO đủ lớn để gửi thông
  /// báo cập nhật dù pha mưa không đổi (vd đã báo "mưa 15:30", dự báo mới nói
  /// 14:20 → cần báo lại ngay vì người dùng có thể ra đường trễ hơn dự tính).
  static const int rainTimeShiftRenotifyMinutes = 15;

  /// Độ lệch (phút) khi mưa DỜI MUỘN hơn thời điểm đã báo — ngưỡng CAO hơn
  /// chiều sớm vì dự báo giờ hay "trôi" dần về sau; báo lại mỗi lần trôi 15'
  /// sẽ thành spam "Cập nhật" cả buổi trong mùa mưa.
  static const int rainTimeShiftLaterRenotifyMinutes = 45;

  /// Khi đã cảnh báo "sắp mưa" TỪ XA (trên ngưỡng này), lúc cơn mưa áp sát
  /// còn ≤ ngưỡng này (phút) sẽ gửi thêm MỘT thông báo nhắc lại — trả lời nhu
  /// cầu "báo trước ~30 phút" kể cả khi cảnh báo đầu bắn từ 2 tiếng trước.
  static const int rainReminderLeadMinutes = 35;

  /// Quan trắc thời tiết hiện tại (`current`) cũ hơn ngưỡng này (phút) so với
  /// thời điểm phân tích thì KHÔNG dùng để khẳng định "đang mưa".
  static const int rainObsMaxAgeMinutes = 30;

  /// Lượng mưa quan trắc 1h gần nhất (mm) đủ lớn để coi là "đang mưa" kể cả
  /// khi mã điều kiện chưa chuyển sang nhóm mưa (cao hơn ngưỡng lọc nhiễu vì
  /// rain1h là số tích lũy, có thể còn dư sau khi mưa vừa tạnh).
  static const double rainObsMm1hThreshold = 0.5;

  /// Ngưỡng pop để một giờ hourly được tin là "chắc chắn mưa" khi nó MÂU THUẪN
  /// với nowcast (nowcast bảo khô). Nowcast ở VN hay bỏ sót mưa nên hourly có
  /// lượng mưa cụ thể + pop ≥ ngưỡng này vẫn được dùng để cảnh báo sớm.
  static const double rainConfidentPopThreshold = 0.6;

  /// Floor xác suất (%) khi nowcast minutely đã XÁC NHẬN đang mưa / sắp mưa —
  /// tránh mâu thuẫn kiểu "Trời đang mưa. Khả năng mưa khoảng 40%."
  static const int minutelyProbabilityFloorPct = 80;

  /// Dữ liệu thời tiết cũ hơn ngưỡng này (phút) thì background worker KHÔNG
  /// sinh cảnh báo (tránh báo pha/giờ sai từ cache khi fetch thất bại).
  static const int alertMaxDataAgeMinutes = 45;

  /// Khoảng cách (mét) di chuyển tối thiểu để cập nhật lại vị trí (tối ưu pin).
  static const int locationDistanceFilterMeters = 200;

  /// Chu kỳ background check thời tiết (phút) MẶC ĐỊNH. Người dùng có thể đổi
  /// trong Settings sang một trong [backgroundIntervalOptions]. Lưu ý:
  /// WorkManager (chỉ dùng khi TẮT foreground service) tối thiểu ~15 phút nên
  /// giá trị <15 chỉ có hiệu lực thực khi foreground service đang bật.
  static const int backgroundIntervalMinutes = 15;

  /// Các mức chu kỳ nền cho người dùng chọn (phút). Chu kỳ ngắn cập nhật kịp
  /// thời hơn nhưng tốn pin/nhiệt và tiêu hạn mức API nhanh hơn (3 call/refresh).
  static const List<int> backgroundIntervalOptions = [5, 10, 15, 30];

  /// --- Khung giờ hoạt động (Active Hours) ---
  /// Ngoài khung giờ này, các lớp trigger nền BỎ QUA việc lấy dữ liệu (mát máy,
  /// tiết kiệm hạn mức API) và alarm exact backstop re-arm đúng vào giờ MỞ khung
  /// thay vì đá CPU dậy mỗi chu kỳ suốt đêm. Bản tin hằng ngày KHÔNG bị chặn bởi
  /// khung giờ (alarm digest riêng, tự làm mới lúc bắn).
  ///
  /// Mặc định BẬT giới hạn giờ (không phải cả ngày) để tránh chạy nền vô ích ban
  /// đêm khi người dùng ngủ.
  static const bool activeHoursAllDayDefault = false;

  /// Giờ MỞ khung mặc định (phút-trong-ngày). 300 = 5:00 — kịp làm mới trước
  /// bản tin sáng 6:30.
  static const int activeHoursStartDefault = 5 * 60;

  /// Giờ ĐÓNG khung mặc định (phút-trong-ngày). 1260 = 21:00.
  static const int activeHoursEndDefault = 21 * 60;

  /// Ngưỡng thay đổi nhiệt độ mạnh giữa hiện tại và vài giờ tới (°C).
  static const double strongTempDeltaC = 5.0;

  /// Ngưỡng thay đổi độ ẩm mạnh (%).
  static const double strongHumidityDeltaPct = 20.0;

  /// Độ ẩm cao gây oi bức (%) — dùng cho ghi chú lưu ý trong app.
  static const int humidityHighPct = 80;

  /// Độ ẩm thấp gây khô (%) — dùng cho ghi chú lưu ý trong app.
  static const int humidityLowPct = 30;

  /// Gió coi là "mạnh" (m/s) để nhắc cẩn thận khi di chuyển (~cấp 5 Beaufort).
  static const double strongWindMs = 10.0;

  /// Khoảng cách tối thiểu (phút) giữa hai lần gọi API làm mới — nhiều trigger
  /// nền (foreground service + alarm exact + WorkManager) cùng chạy 15' sẽ tự
  /// khử trùng lặp: cache còn tươi hơn ngưỡng này thì KHÔNG gọi API (tiết kiệm
  /// hạn mức 1000 call/ngày, mỗi refresh tốn 3 call).
  static const int minRefreshGapMinutes = 12;

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
  /// background → fallback sang toạ độ đã lưu (LastLocationStore) thay vì bỏ
  /// qua. 24h vì máy đứng yên qua đêm ở nhà là bình thường, vị trí cũ vẫn đúng
  /// khu vực; điều này cho phép bản tin sáng dùng dữ liệu tươi.
  static const int backgroundLastKnownMaxAgeHours = 24;

  // --- Bản tin thời tiết hằng ngày ---

  /// Mốc giờ bản tin buổi sáng mặc định (phút-trong-ngày). 390 = 6:30.
  static const int digestDefaultMorningMinutes = 6 * 60 + 30;

  /// Mốc giờ bản tin buổi chiều mặc định (phút-trong-ngày). 990 = 16:30.
  static const int digestDefaultEveningMinutes = 16 * 60 + 30;

  /// Danh sách mốc giờ bản tin MẶC ĐỊNH (phút-trong-ngày). Người dùng có thể
  /// thêm/xóa bao nhiêu mốc tùy ý trong màn Thời tiết. Mặc định giữ 2 mốc quen
  /// thuộc: 6:30 sáng & 16:30 chiều.
  static const List<int> digestDefaultTimes = [
    digestDefaultMorningMinutes,
    digestDefaultEveningMinutes,
  ];

  /// Số mốc bản tin tối đa (giới hạn dải alarm ID cấp phát trong NotificationIds).
  static const int digestMaxSlots = 64;

  /// Ngưỡng chỉ số UV để nhắc chống nắng trong bản tin.
  static const double digestUvWarnThreshold = 6.0;

  /// Ngưỡng xác suất mưa (pop 0..1) coi một giờ là "có khả năng mưa" khi quét
  /// dự báo cả ngày cho bản tin (BuildRainOutlook). Thấp hơn ngưỡng cảnh báo
  /// tức thời vì đây là thông tin định hướng ("chiều nay có thể mưa").
  static const double rainOutlookPopThreshold = 0.4;

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

  /// Reverse geocoding Nominatim (OpenStreetMap) — trả địa chỉ tiếng Việt chi
  /// tiết (đường → phường → quận → thành phố) tốt hơn plugin nền tảng ở VN.
  /// Miễn phí, không cần key nhưng chính sách OSM yêu cầu: gửi `userAgent` rõ
  /// ràng và tối đa ~1 request/giây (app chỉ gọi khi đổi vị trí/refresh nên OK).
  static const String nominatimReverseUrl =
      'https://nominatim.openstreetmap.org/reverse';

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
