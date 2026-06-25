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
- **Mobile:** entity `Coordinates` · `LocationDataSource` (geolocator) · `LocationRepositoryImpl` · providers `currentLocationProvider` (Future), `locationStreamProvider` (Stream)
- **Key logic:** `PermissionService.ensureLocationPermission` xử lý denied/deniedForever; `distanceFilter=200m` (AppConfig) để tiết kiệm pin; trả `Either<Failure, Coordinates>`.

### Thời tiết (weather)
- **Status:** ✅ done
- **Backend:** — (gọi thẳng OpenWeatherMap **One Call 4.0**)
- **Mobile:** entities `WeatherData/CurrentWeather/MinutelyForecast/HourlyForecast/RainStatus/WeatherCondition` · `WeatherMapper` (JSON→entity) · `WeatherRemoteDataSource` (Dio, 4.0 adapter) · `WeatherLocalDataSource` (Drift) · `WeatherRepositoryImpl` · usecases `AnalyzeRain`, `DetectEnvChange` · providers `weatherProvider`, `rainStatusProvider`, `weatherConditionProvider` · screen `WeatherScreen` + widgets (current_card, condition_card, hourly_list, rain_alert_banner)
- **Key logic:** **4.0 adapter** — `WeatherRemoteDataSource` gọi song song `/onecall/current` + `/timeline/15min` + `/timeline/1h`, chuẩn hoá về shape gộp (current+minutely+hourly) nên `WeatherMapper`/cache/repo không đổi. Offline-first (online→remote+cache, offline→cache, rỗng→`CacheFailure`). `AnalyzeRain` tính phút theo **mốc thời gian** (độc lập độ phân giải: 1' của 3.0 hay 15' của 4.0), chống nhiễu `dryStreakToConfirmStop=3`; fallback `hourly`. Parser JSON thủ công guard null.

### Phân loại tình hình thời tiết (weather condition)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** entity `WeatherCondition` (+ enum `WeatherCategory`, `WeatherSeverity`) · `WeatherCondition.classify(id, rainMmH)` · provider `weatherConditionProvider` · widget `ConditionCard`. `CurrentWeather.conditionId` parse từ `weather[0].id`.
- **Key logic:** map mã OWM → nắng/ít mây/nhiều mây/u ám/sương mù/mưa nhỏ-vừa-to-rất to/dông/bão lớn/lốc xoáy/tuyết, kèm nhãn VI + lời khuyên + mức độ (info/notice/warning/severe). Lượng mưa lớn có thể nâng cấp cường độ (vd 500 + rainMmH≥2.5 → mưa to).

### Thông báo thông minh (alerts)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `WeatherAlert` · `BuildWeatherAlerts` (usecase) · `AlertStateStore` (SharedPreferences) · `NotificationService` (core/notifications) · `BackgroundScheduler` + `callbackDispatcher` (core/background, WorkManager)
- **Key logic:** WorkManager periodic 15' chạy trong **isolate riêng** (tự dựng DI, không Riverpod). Sinh **3 nhóm** thông báo: (1) thời điểm mưa (RainStatus), (2) tình hình thời tiết (WeatherCondition), (3) thay đổi nhiệt/ẩm (EnvChange). Chống spam: chỉ phát khi PHA mưa / NHÓM thời tiết đổi so với trạng thái lưu ở `AlertStateStore` (phase + category + envNotified); notification ID cố định theo loại để thay thế thay vì chồng chất.

### Module 1 — Bản đồ & Tin tức (Phase 2)
- **Status:** 📋 planned (STUB)
- **Mobile:** `NewsRepository` (interface) + `NewsRepositoryStub.getNewsAround` ném `UnimplementedError`.
- **Key logic:** chờ tích hợp Map SDK + RSS/News API.

### Module 2 — Fixed Route POI (Phase 2)
- **Status:** 🚧 in progress (lưu trữ xong, quét POI là STUB)
- **Mobile:** entities `RoutePoint`, `Poi` · `RouteLocalDataSource` (Drift CRUD — hoạt động) · `PoiRepositoryStub` (CRUD ủy quyền local; `scanPoisAlongRoute` ném `UnimplementedError`).
- **Key logic:** bảng `fixed_route_points` dùng được ngay để lưu lộ trình; `scanPoisAlongRoute(radiusMeters, types)` chờ Google Places Nearby Search.

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
| `weatherProvider` | FutureProvider | weather | `currentLocationProvider` + `weatherRepositoryProvider` |
| `rainStatusProvider` | Provider | weather | `weatherProvider` |
| `weatherConditionProvider` | Provider | weather | `weatherProvider` |
| `*RepositoryProvider`, `*DataSourceProvider` | Provider (DI) | location/weather | hạ tầng ở `core/di/providers.dart` |

> Loại: `FutureProvider` (read) · `StateNotifierProvider` (mutation) · `StreamProvider` · `Provider`.
