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
weatherProvider (StreamProvider — stale-while-revalidate)
   │ 1) getCachedWeather(coords) → yield cache NGAY (UI hiển thị tức thì)
   │ 2) nếu thiếu cache hoặc cache.needsRevalidate (≥15') → getWeather(coords):
   ├─(online)─▶ WeatherRemoteDataSource → 3× Dio GET (4.0: /current, /timeline/15min, /timeline/1h)
   │             → chuẩn hoá shape gộp → cache Drift → yield dữ liệu tươi
   └─(offline/lỗi)▶ có cache → giữ cache (im lặng); không cache → throw Failure
   ▼  (currentLocation ưu tiên last-known → mở app nhanh; AppLifecycleListener resume→invalidate)
WeatherMapper.fromOneCallJson → WeatherData (AsyncValue)
   ▼
UI: AppErrorWidget / PermissionDeniedWidget khi lỗi; data → CurrentCard + HourlyList
   + rainStatusProvider (AnalyzeRain, kèm probabilityPct) → RainAlertBanner
   + connectivityStatusProvider → badge "dữ liệu cũ" (offline thật vs đang làm mới)
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
resolveBackgroundCoords (last-known ≤24h / fallback LastLocationStore)
   ▼  (null → bỏ lần này; không còn chặn cứng 3h → fetch được qua đêm)
WeatherRepository.getWeather(forceRefresh)
   ▼  (data.age > 45' — cache cũ do fetch fail → BỎ sinh cảnh báo, nhảy tới bước lập lịch digest)
AnalyzeRain(now) [lọc điểm quá khứ, trả changeAt + phút-từ-now] + DetectEnvChange
   ▼
BuildWeatherAlerts(rain, env, previousPhase + previousChangeAt từ AlertStateStore)
   │ chỉ sinh alert khi PHA đổi (chống spam);
   │ NGOẠI LỆ: pha giữ nguyên nhưng changeAt lệch ≥15' → alert "Cập nhật:" (cùng ID)
   │ giờ HH:MM format từ changeAt (không cộng phút vào now → hết drift)
   ▼
NotificationService.show(id cố định theo loại) → AlertStateStore.write(phase + changeAt mới)
   ▼ (cùng lần chạy, kênh độc lập)
NotificationPrefsStore.read() → scheduleDigests(prefs)  [chỉ lập/huỷ lịch, KHÔNG bake nội dung]
```

### 2b. Bản tin hằng ngày — alarm FETCH TƯƠI tại thời điểm bắn
```
scheduleDigests(prefs) được gọi để lịch khớp cài đặt (không cần WeatherData):
  • main `_bootstrap` (mở app)                       ┐
  • NotificationSettingsController (đổi enabled/giờ) ├─▶ AndroidAlarmManager.periodic
  • background_worker._runWeatherCheck               ┘     (id morning/evening; exact+wakeup+allowWhileIdle+rescheduleOnReboot)
   ▼  enabled=false → AndroidAlarmManager.cancel cả 2 id
Đến mốc giờ → AlarmManager đánh thức isolate → digestAlarmCallback(id):
   resolveBackgroundCoords → getWeather(forceRefresh) → BuildDailyDigest
   (gồm BuildRainOutlook: quét hourly cả ngày → mưa theo buổi)
   → NotificationService.show(id)   ← DỮ LIỆU TƯƠI, không phải text lập lịch sẵn
```

### 6. Ghi chú — ghim sticky & nút "Đã đọc"
```
NotesScreen/NoteEditScreen → notesControllerProvider (save/togglePin/toggleItemDone…)
   ▼ NoteLocalDataSource (Drift: notes + note_items)
   ▼ NoteNotificationService.sync(note, items)   ← PHỄU DUY NHẤT
      cancelAll(9 slot: 10000+noteId*16+slot) → done? dừng
      → pinned? showPinned (ongoing+autoCancel:false+onlyAlertOnce, channel note_pinned low, action "Đã đọc")
      → buildReminderSlots(remindAt, repeat, weekdaysMask) → zonedSchedule exact (slot 8 một-lần/ngày; slot 1..7 theo thứ)
Nhấn "Đã đọc" (cancelNotification native gỡ khay, KHÔNG giết alarm)
   ▼ ActionBroadcastReceiver → onNotificationActionBackground (isolate riêng: init tz + AppDatabase mới)
   setPinned(false) → cancel(slot 0) → syncReminders(1..8, hết sticky)  [note GIỮ NGUYÊN trong app]
   ▼ main isolate không tự thấy write → AppLifecycleListener.onResume → invalidate(notesControllerProvider)
Re-assert (reboot / Android 14 "Xoá tất cả"):
   main._bootstrap  ┬─▶ reassertNoteNotifications(db): show lại mọi note pinned&&!done + re-sync lịch
   worker 15' (đầu chu kỳ, TRƯỚC weather check — không bị guard vị trí chặn) ┘
Chạm thân notification → onNotificationTap / getLaunchDetails (cold-launch) → appRouter.push('/notes')
```

### Error mapping (đã áp dụng)
- Dio error → `api_client.dart` map sang `ServerException`/`NetworkException`.
- Repository bắt exception → `Failure`. UI hiển thị qua `extractUserMessage(e)`.
- OpenWeatherMap trả lỗi ở field `message` (không phải `detail`).
