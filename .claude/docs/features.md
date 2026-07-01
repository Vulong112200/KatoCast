# Features — Danh sách chức năng & trạng thái

> Cập nhật qua `/sync-docs`. Mỗi feature có format chuẩn: **Status / Backend / Mobile / Key logic**.

## Format chuẩn cho mỗi feature

```
### <Tên feature>
- **Status:** 📋 planned | 🚧 in progress | ✅ done
- **Backend:** model · schema · repository · service · endpoints liên quan
- **Mobile:** models · api_service · repository · providers · screens
- **Key logic:** điểm logic quan trọng/dễ sai (vd normalize JSON, sync queue, edge cases)
```

---

## Features

> Phase 1 client-only (không backend). Đường dẫn dưới đây thuộc `mobile/lib/`.

### Định vị (location)
- **Status:** ✅ done
- **Backend:** — (client-only)
- **Mobile:** entities `Coordinates`, `Place` · `LocationDataSource` (geolocator + geocoding) · `LocationRepositoryImpl` · `LastLocationStore` (SharedPreferences) · providers `currentLocationProvider` (Future), `locationStreamProvider` (Stream), `currentPlaceProvider` (Future<Place?>)
- **Key logic:** `PermissionService.ensureLocationPermission` xử lý denied/deniedForever; `distanceFilter=200m` (AppConfig) để tiết kiệm pin; trả `Either<Failure, Coordinates>`. **Reverse geocoding**: `reverseGeocode` (geocoding) → `Place` với `shortLabel` (ưu tiên phường/quận → tỉnh; fallback toạ độ); lỗi/không có dịch vụ → null (không chặn UI thời tiết). **`LastLocationStore`**: `currentLocationProvider` lưu toạ độ mỗi lần định vị thành công để background isolate (`resolveBackgroundCoords`) fallback khi `getLastKnownPosition` null/quá cũ (>24h) — bảo đảm worker/bản tin vẫn fetch qua đêm khi máy đứng yên.

### Giao diện & cá nhân hóa (theme)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `core/theme/` — `theme_palettes.dart` (`AppPalette` + `kAppPalettes`), `weather_theme.dart` (`seedForCategory`), `app_theme.dart` (`buildAppTheme`), `theme_controller.dart` (`ThemeSettings` + `ThemeController` StateNotifier, provider `themeControllerProvider`) · màn `SettingsScreen` (`features/settings/`)
- **Key logic:** 4 mức gộp 1 hệ thống — Sáng/Tối/Hệ thống (`ThemeMode`), bảng màu chọn sẵn (seed), Material You (`dynamic_color` `DynamicColorBuilder`), đổi màu theo thời tiết. **Precedence seed** (tính ở `main.dart`): weatherAdaptive (theo `weatherConditionProvider`) > useDynamicColor (corePalette hệ thống) > paletteId. Cài đặt lưu/đọc SharedPreferences. Settings còn có trạng thái quyền thông báo + guide whitelist pin (`requestIgnoreBatteryOptimizations`).

### Thời tiết (weather)
- **Status:** ✅ done
- **Backend:** — (gọi thẳng OpenWeatherMap **One Call 4.0**)
- **Mobile:** entities `WeatherData/CurrentWeather/MinutelyForecast/HourlyForecast/RainStatus/WeatherCondition` · `WeatherMapper` (JSON→entity) · `WeatherRemoteDataSource` (Dio, 4.0 adapter) · `WeatherLocalDataSource` (Drift) · `WeatherRepositoryImpl` (+ `getCachedWeather`) · usecases `AnalyzeRain`, `DetectEnvChange` · providers `weatherProvider` (StreamProvider), `connectivityStatusProvider`, `rainStatusProvider`, `weatherConditionProvider` · screen `WeatherScreen` + widgets (current_card, condition_card, hourly_list, rain_alert_banner)
- **Key logic:** **4.0 adapter** — `WeatherRemoteDataSource` gọi song song `/onecall/current` + `/timeline/15min` + `/timeline/1h`, chuẩn hoá về shape gộp (current+minutely+hourly) nên `WeatherMapper`/cache/repo không đổi. **Stale-while-revalidate**: `weatherProvider` (StreamProvider) phát cache ngay (`getCachedWeather`, không gọi mạng) rồi mới gọi API NẾU thiếu cache hoặc cache `needsRevalidate` (≥`weatherRevalidateMinutes`=15'); fetch lỗi mà có cache → giữ cache. `currentLocation` ưu tiên last-known → mở app nhanh, và **lưu toạ độ vào `LastLocationStore`** để background dùng khi last-known hết hạn. `AppLifecycleListener` (main) làm mới khi resume. Badge "dữ liệu cũ" dùng `connectivityStatusProvider` để nói đúng offline vs đang làm mới. `AnalyzeRain` tính phút theo **mốc thời gian** (1'/15'), chống nhiễu `dryStreakToConfirmStop=3`, kèm `probabilityPct` (từ `hourly.pop`), guard tầm nhìn `rainSoonHorizonMinutes=120'` ở fallback hourly. **`BuildRainOutlook`** quét `hourly` cả ngày → câu tóm tắt mưa theo buổi cho bản tin (ngưỡng `rainOutlookPopThreshold`=0.4). Parser JSON thủ công guard null.

### Phân loại tình hình thời tiết (weather condition)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** entity `WeatherCondition` (+ enum `WeatherCategory`, `WeatherSeverity`) · `WeatherCondition.classify(id, rainMmH)` · provider `weatherConditionProvider` · widget `ConditionCard`. `CurrentWeather.conditionId` parse từ `weather[0].id`.
- **Key logic:** map mã OWM → nắng/ít mây/nhiều mây/u ám/sương mù/mưa nhỏ-vừa-to-rất to/dông/bão lớn/lốc xoáy/tuyết, kèm nhãn VI + lời khuyên + mức độ (info/notice/warning/severe). Lượng mưa lớn có thể nâng cấp cường độ (vd 500 + rainMmH≥2.5 → mưa to).

### Thông báo thông minh (alerts)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `WeatherAlert` · `BuildWeatherAlerts` (usecase) · `AlertStateStore` (SharedPreferences) · `NotificationService` (core/notifications, `show` + `scheduleDaily`/`cancel`) · `BackgroundScheduler` + `callbackDispatcher` (core/background, WorkManager)
- **Key logic:** WorkManager periodic 15' chạy trong **isolate riêng** (tự dựng DI, không Riverpod). Sinh **3 nhóm** thông báo: (1) thời điểm mưa (RainStatus), (2) tình hình thời tiết (WeatherCondition), (3) thay đổi nhiệt/ẩm (EnvChange). Chống spam: chỉ phát khi PHA mưa / NHÓM thời tiết đổi so với trạng thái lưu ở `AlertStateStore` (phase + category + envNotified); notification ID cố định theo loại để thay thế thay vì chồng chất. Nội dung mưa kèm **giờ đồng hồ (HH:MM)** + **% khả năng mưa** (`rain.probabilityPct`); phân biệt "sắp tạnh" (rainStoppingSoon) vs "đã tạnh" (dry). Mọi thông báo dùng `BigTextStyleInformation` (mở rộng đầy đủ, không cắt chữ).

### Bản tin thời tiết hằng ngày (daily digest)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `DailyDigest` + `BuildDailyDigest` (usecase) · `BuildRainOutlook` (usecase mưa cả ngày) · `NotificationPrefsStore` + `DigestPrefs`/`DigestSlot` (SharedPreferences) · `scheduleDigests` (`digest_scheduler.dart`) · `digestAlarmCallback` (`core/background/digest_alarm.dart`) · `NotificationSettingsController` + provider `notificationSettingsProvider` · UI `_DailyDigestSettings` trong `SettingsScreen` · lập lịch qua **`android_alarm_manager_plus`** (ID `dailyDigestMorning=1005`, `dailyDigestEvening=1006`)
- **Key logic:** kênh thông báo **độc lập** với cảnh báo sự kiện — tóm tắt nhiệt độ + cảm giác như + hi/lo 24h + tình hình `WeatherCondition` + lời khuyên + **outlook mưa CẢ NGÀY theo buổi** (`BuildRainOutlook`: quét `hourly` còn lại của hôm nay, gom khung mưa sáng/chiều/tối, ví dụ "Chiều có mưa (~14:00–16:00, khả năng ~70%). Sáng & tối khô ráo." / "Hôm nay ít khả năng mưa.") + gợi ý mưa tức thời từ `AnalyzeRain` (giờ + %) + nhắc UV nếu `uvi≥digestUvWarnThreshold` + "Cập nhật lúc HH:MM" (theo `fetchedAt`). **Cơ chế = alarm chạy code nền** (`AndroidAlarmManager.periodic` lặp ngày, `exact + wakeup + allowWhileIdle + rescheduleOnReboot`): tại mốc giờ, `digestAlarmCallback` (isolate riêng, tự dựng DI) **FETCH dữ liệu tươi rồi mới hiển thị** — sửa lỗi cũ (`zonedSchedule` bake sẵn text → hiện dữ liệu cũ). `scheduleDigests(DigestPrefs)` chỉ lập/huỷ lịch (không truyền `WeatherData`), gọi lại ở 3 nơi: **main `_bootstrap`**, **`NotificationSettingsController`** (đổi enabled/giờ), **`background_worker._runWeatherCheck`**. Toạ độ nền lấy qua `resolveBackgroundCoords` (`core/background/background_location.dart`) — last-known (≤`backgroundLastKnownMaxAgeHours`=24h) hoặc fallback `LastLocationStore`. Hai mốc `morningMinutes`/`eveningMinutes` (mặc định 390/990 = 6h30/16h30) lưu phút-trong-ngày, chỉnh qua time picker; công tắc `enabled` (tắt → `cancel` cả 2). **AndroidManifest** khai báo `USE_EXACT_ALARM`/`SCHEDULE_EXACT_ALARM` (alarm) + receiver flutter_local_notifications (còn dùng cho `NotificationService.scheduleDaily` fallback).

### Module 1 — Bản đồ & Tin tức
- **Status:** ✅ done
- **Backend:** — (OpenStreetMap + RSS, miễn phí, không key)
- **Mobile:** `NewsItem` · `RssDataSource` (Dio + `xml` parse RSS) · `NewsRepositoryImpl` · providers `rssDataSourceProvider`, `newsRepositoryProvider`, `newsProvider` · `MapScreen` (`/map`)
- **Key logic:** bản đồ `flutter_map` (tile OSM) + lớp phủ mưa OWM (`precipitation_new`, dùng lại `owmApiKey`); marker vị trí hiện tại. Tin tức từ RSS VnExpress thời tiết — parse RFC-822 pubDate thủ công, lỗi/parse fail → list rỗng (không chặn bản đồ). RSS không geo-tag nên `center`/`radius` chưa lọc theo vị trí. Mở link bằng `url_launcher`.

### Module 2 — Fixed Route POI
- **Status:** ✅ done
- **Backend:** — (Overpass/OSM, miễn phí, không key)
- **Mobile:** entities `RoutePoint`, `Poi` · `RouteLocalDataSource` (Drift CRUD) · `OverpassDataSource` (Dio riêng → Overpass QL) · `PoiRepositoryImpl` · providers `routeLocalDataSourceProvider`, `overpassDataSourceProvider`, `poiRepositoryProvider`, `routeControllerProvider` (StateNotifier) · `RouteScreen` (`/routes`, flutter_map) · widget `poi_visuals` (icon/màu/nhãn theo PoiType)
- **Key logic:** chạm bản đồ / "Thêm vị trí" → lưu `RoutePoint` (Drift, routeId `default`). `scanPoisAlongRoute`: Overpass QL `around:radius` cho mỗi (điểm × loại), `out center` (bắt cả node & way); map tag OSM (`amenity=restaurant/fuel/cafe`, `shop=supermarket`) → `PoiType`; khử trùng theo toạ độ làm tròn + loại; `distanceToRouteMeters` = khoảng cách tới điểm lộ trình gần nhất (`Geolocator.distanceBetween`); lọc trong bán kính, sắp xếp theo độ gần. **Chịu lỗi mạng:** `OverpassDataSource` thử lần lượt nhiều mirror (`AppConfig.overpassEndpoints`) + gửi `User-Agent`; hết mirror/response sai shape → ném `ServerException`, controller hiển thị qua `extractUserMessage` (không nuốt lỗi). `RouteState.scanned` phân biệt "chưa quét" với "quét xong nhưng rỗng".

---

## Database Tables Status

> DB cục bộ Drift (`mobile/lib/core/database/app_database.dart`), schemaVersion = 1.

| Table | Status | Migration | Ghi chú |
|-------|--------|-----------|---------|
| `weather_cache` | ✅ | Drift v1 | cache JSON One Call theo locationKey |
| `fixed_route_points` | ✅ | Drift v1 | lộ trình cố định (Module 2) |

---

## Mobile Providers — State Map

| Provider | Loại | Feature | Watch / phụ thuộc |
|----------|------|---------|-------------------|
| `currentLocationProvider` | FutureProvider | location | `locationRepositoryProvider` |
| `locationStreamProvider` | StreamProvider | location | `locationRepositoryProvider` |
| `currentPlaceProvider` | FutureProvider | location | `currentLocationProvider` + `locationRepositoryProvider` |
| `themeControllerProvider` | StateNotifierProvider | theme | SharedPreferences; UI Settings + `main.dart` |
| `notificationSettingsProvider` | StateNotifierProvider | alerts (digest) | `NotificationPrefsStore` (SharedPreferences); UI Settings |
| `routeControllerProvider` | StateNotifierProvider | fixed_route | `poiRepositoryProvider` (Drift + Overpass) |
| `poiRepositoryProvider` | Provider (DI) | fixed_route | `routeLocalDataSourceProvider` + `overpassDataSourceProvider` |
| `newsProvider` | FutureProvider | map_news | `currentLocationProvider` + `newsRepositoryProvider` (RSS) |
| `weatherProvider` | FutureProvider | weather | `currentLocationProvider` + `weatherRepositoryProvider` |
| `rainStatusProvider` | Provider | weather | `weatherProvider` |
| `weatherConditionProvider` | Provider | weather | `weatherProvider` |
| `*RepositoryProvider`, `*DataSourceProvider` | Provider (DI) | location/weather | hạ tầng ở `core/di/providers.dart` |

> Loại: `FutureProvider` (read) · `StateNotifierProvider` (mutation) · `StreamProvider` · `Provider`.
