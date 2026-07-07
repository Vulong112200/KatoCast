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
UI: AppErrorWidget / PermissionDeniedWidget khi lỗi; data → CurrentCard (UV+band, mây, hi/lo) + HourlyList
   + rainStatusProvider (AnalyzeRain: probabilityPct + rainEndsAt) → RainAlertBanner
   + BuildAdvisories → AdvisoryCard "Lưu ý hôm nay" (tình hình + UV + ẩm + gió + mưa)
   + connectivityStatusProvider → badge "dữ liệu cũ" (offline thật vs đang làm mới)
   + currentPlaceProvider → getPlace (Nominatim OSM ưu tiên → fallback plugin geocoding) → AppBar (shortLabel) + header thân màn hình (fullLabel đầy đủ: đường→phường→quận→tỉnh, không cắt)
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

### 2. Thông báo thông minh (background → LÕI runWeatherCheck)
```
applyBackgroundTriggers() [main._bootstrap + backgroundSettingsProvider khi đổi cài đặt]:
   ▼ đọc BackgroundPrefsStore.foregroundEnabled
   ├─ BẬT  → startWeatherForegroundService + scheduleWeatherAlarm (BACKSTOP song song);
   │          BackgroundScheduler.cancel (bỏ WorkManager). FG chính + alarm cứu khi FG bị giết.
   └─ TẮT  → stopWeatherForegroundService; BackgroundScheduler.initialize + scheduleWeatherAlarm
main._bootstrap CÒN gọi runWeatherCheck() NGAY (fire-and-forget) → cảnh báo tức thì + init AlertStateStore.
LỚP ĐANG HOẠT ĐỘNG gọi runWeatherCheck (isolate riêng tự dựng DI):
  • foreground_service: onRepeatEvent mỗi intervalMinutes (5/10/15/30'), allowWakeLock
      (allowWifiLock=false); _tick RE-ASSERT ghim ghi chú TRƯỚC rồi runWeatherCheck
  • weather_alarm: oneShotAt exact+allowWhileIdle, LUÔN tự re-arm (backstop thường trực)
  • WorkManager periodic (clamp ≥15'): chỉ khi FG tắt
   ▼ ⚠️ Vuốt tắt app trên OEM (Nubia/MyOS…) = force-stop → hủy sạch alarm+FG; chỉ cứu bằng
   ▼    bật Tự khởi động + Không giới hạn pin (onboarding + MainActivity MethodChannel katocast/oem)
runWeatherCheck (core/background/weather_check.dart):
   resolveBackgroundCoords (last-known ≤24h / fallback LastLocationStore) → null → dừng
   ▼  GUARD QUOTA bám chu kỳ: getCachedWeather → cache tươi hơn (intervalMinutes−1') → DÙNG CACHE,
   │  KHÔNG gọi API; ngược lại getWeather (luôn gọi remote khi online)
   ▼  (data.age > 45' → BỎ sinh cảnh báo, nhảy tới bước lập lịch digest)
AnalyzeRain(now) [changeAt + rainEndsAt/duration + probabilityPct] + DetectEnvChange
   ▼
BuildWeatherAlerts(rain, env, previousPhase + previousChangeAt từ AlertStateStore)
   │ chỉ sinh alert khi PHA đổi; NGOẠI LỆ: changeAt lệch ≥15' → "Cập nhật:" (cùng ID)
   │ nội dung mưa: giờ bắt đầu (HH:MM từ changeAt) + % + giờ tạnh/thời lượng (rainEndsAt)
   ▼
NotificationService.show(id cố định) → AlertStateStore.write(phase + changeAt mới)
   ▼ (foreground service còn updateService: thông báo thường trực live nhiệt độ + tình hình)
NotificationPrefsStore.read() → scheduleDigests(prefs)  [re-arm mọi mốc digest mỗi chu kỳ]
```

### 2b. Bản tin hằng ngày — NHIỀU MỐC + alarm FETCH TƯƠI tại thời điểm bắn
```
DigestSettingsCard (màn Weather) → notificationSettingsProvider.addTime/removeTime/updateTime
   ▼ (ghi NotificationPrefsStore.setTimes; nếu thiếu quyền exact → nút xin requestExactAlarmPermission)
scheduleDigests(prefs) được gọi để lịch khớp cài đặt (không cần WeatherData):
  • main `_bootstrap` (mở app)                        ┐
  • NotificationSettingsController (đổi enabled/mốc)  ├─▶ hủy toàn dải (digestBase..+maxSlots) rồi
  • runWeatherCheck (mỗi chu kỳ → tự chữa chuỗi)      ┘   for i,minutes: scheduleDigestSlot(digestBase+i)
   ▼  enabled=false → hủy toàn dải, dừng                    ▼ canScheduleExactAlarms?
   ▼  DÙNG oneShotAt, KHÔNG periodic (setRepeating         ├─ có → exact:true
   │  bị Doze hoãn → bản tin SÁNG không nổ)                └─ KHÔNG → exact:false (inexact, VẪN nổ
   ▼                                                            gần đúng — không SecurityException im lặng)
Đến mốc giờ → AlarmManager đánh thức isolate → digestAlarmCallback(id):
   ├─ id == digestTest(1099) → _runDigestTest: chỉ show thông báo xác nhận, KHÔNG fetch/re-arm
   └─ id >= digestBase → index = id − digestBase → resolveBackgroundCoords → getWeather → BuildDailyDigest
        (BuildRainOutlook mưa theo buổi + UvAdvice lời khuyên UV theo mức)
        → NotificationService.show(id)   ← DỮ LIỆU TƯƠI
        → RE-ARM: scheduleDigestSlot(id, times[index]) cho NGÀY MAI (vẫn re-arm khi thiếu vị trí/offline;
          KHÔNG re-arm nếu index đã bị xóa hoặc !enabled)

TỰ CHẨN ĐOÁN: DigestSettingsCard "Đặt bản tin thử sau 1 phút" → scheduleDigestTest → oneShotAt(now+1',
   digestTest). Nổ khi khóa màn hình = lập lịch OK; vuốt tắt app rồi KHÔNG nổ = force-stop OEM → bật Autostart.
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
