# Call Flows — Luồng hoạt động của hệ thống

> Cập nhật qua `/sync-docs` — **chỉ khi** có flow mới, endpoint đổi logic, hoặc thêm step vào flow hiện có.
> Mô tả theo chuỗi: UI → provider → repository → (api_service ↔ backend) → service → repo → DB.

## Flow mẫu — chuẩn để mô tả (template)

```
[Mobile]  Screen (ConsumerWidget)
   │ user action
   ▼
StateNotifierProvider.method()
   │
   ▼
Repository  ──(online)──▶ api_service ──Dio──▶ [Backend] api/v1/endpoint
   │  (offline)                                      │ Depends(get_current_active_user)
   ▼                                                 ▼
Drift local + sync_queue (status=pending)        Service (business logic)
                                                     ▼
                                                  Repository (CRUD)
                                                     ▼
                                                  SQLAlchemy → PostgreSQL
   ◀── response (Pydantic v2; Decimal → String) ──┘
   │ normalize JSON ở api_service nếu cần
   ▼
ref.invalidate(provider) → UI rebuild
```

## Các flow cross-cutting (chuẩn dự kiến)

### Auth & token refresh
- 401 từ backend → interceptor trong `api_client.dart` tự refresh token → retry.
- Refresh fail → logout → GoRouter redirect về `/login`.

### Offline-first sync
- Ghi local (Drift) trước → enqueue vào `sync_queue` (status=`pending`).
- Khi online: worker đẩy queue lên backend → cập nhật status → resolve conflict.
- Query kiểm tra: `SELECT * FROM sync_queue WHERE status='pending'`.

### Error mapping
- Backend FastAPI trả lỗi ở field `detail` (không phải `message`) → map trong `api_client.dart`.
- UI hiển thị qua `extractUserMessage(e)`.

---

## Flows thực tế

### 1. Hiển thị thời tiết (foreground)
```
WeatherScreen (ConsumerWidget)
   │ watch weatherProvider
   ▼
weatherProvider ── await ──▶ currentLocationProvider ──▶ LocationRepository.getCurrentLocation()
   │                                                          │ PermissionService.ensureLocationPermission()
   ▼                                                          ▼ (denied → PermissionFailure)
WeatherRepository.getWeather(coords)
   ├─(online)─▶ WeatherRemoteDataSource → 3× Dio GET (4.0: /current, /timeline/15min, /timeline/1h)
   │             → chuẩn hoá về shape gộp → cache vào Drift (WeatherCache)
   └─(offline)▶ WeatherLocalDataSource đọc cache (rỗng → CacheFailure)
   ▼
WeatherMapper.fromOneCallJson → WeatherData (Either<Failure, WeatherData>)
   ▼
UI: AppErrorWidget / PermissionDeniedWidget khi lỗi; data → CurrentCard + HourlyList
   + rainStatusProvider (AnalyzeRain) → RainAlertBanner
   + currentPlaceProvider (reverse geocoding) → tên địa danh trên AppBar
```

### 3. Chọn / áp dụng theme
```
SettingsScreen → themeControllerProvider.notifier.setMode/setPalette/setUseDynamicColor/setWeatherAdaptive
   ▼ (ghi SharedPreferences, cập nhật state)
main.dart build: watch themeControllerProvider (+ weatherConditionProvider)
   ▼ DynamicColorBuilder
chọn seed theo precedence: weatherAdaptive > useDynamicColor > paletteId
   ▼ buildAppTheme(light/dark) → MaterialApp.router(theme/darkTheme/themeMode) → rebuild
```

### 4. Quét POI dọc lộ trình (Module 2)
```
RouteScreen → chạm bản đồ / "Thêm vị trí" → routeController.addPoint → RouteLocalDataSource (Drift)
   ▼ chọn loại + bán kính → routeController.scan
PoiRepositoryImpl.scanPoisAlongRoute → OverpassDataSource (POST Overpass QL around:radius)
   ▼ parse elements → map tag→PoiType → khử trùng → Geolocator.distanceBetween (lọc bán kính, sort)
state.pois → MarkerLayer trên flutter_map + ListView (tên · loại · khoảng cách)
```

### 5. Bản đồ & Tin tức (Module 1)
```
MapScreen → flutter_map (tile OSM + lớp mưa OWM) center theo currentLocationProvider
   + newsProvider → NewsRepositoryImpl → RssDataSource (GET RSS → xml parse → NewsItem[])
   ▼ ListView tin; tap → url_launcher mở trình duyệt
```

### 2. Thông báo thông minh (background — WorkManager)
```
WorkManager periodic 15' → callbackDispatcher (isolate riêng, tự dựng DI)
   ▼
Geolocator.getLastKnownPosition → WeatherRepository.getWeather(forceRefresh)
   ▼
AnalyzeRain + DetectEnvChange → BuildWeatherAlerts(rain, env, previousPhase từ AlertStateStore)
   │ chỉ sinh alert khi PHA đổi (chống spam)
   ▼
NotificationService.show(id cố định theo loại) → AlertStateStore.write(phase mới)
   ▼ (cùng lần chạy, kênh độc lập)
_maybeSendDailyDigest: NotificationPrefsStore.read()
   │ nếu enabled & nowMinutes ∈ [mốc, mốc+digestWindowMinutes) & lastSentDay≠hôm nay
   ▼
BuildDailyDigest(data) → NotificationService.show(dailyDigest) → markSent(slot, yyyymmdd)
```

### Error mapping (đã áp dụng)
- Dio error → `api_client.dart` map sang `ServerException`/`NetworkException`.
- Repository bắt exception → `Failure`. UI hiển thị qua `extractUserMessage(e)`.
- OpenWeatherMap trả lỗi ở field `message` (không phải `detail`).
