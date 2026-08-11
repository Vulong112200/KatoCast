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

### 0. Khởi động app & CHUỖI XIN QUYỀN (thứ tự có chủ ý — `main._bootstrap`)
```
main()  ──▶ ensureTimezoneInitialized()   # nạp tzdata + set tz.local + LƯU tên múi giờ vào prefs
        ──▶ AndroidAlarmManager.initialize()
        ──▶ runApp(ProviderScope)
              │
   frame ĐẦU: WeatherScreen.build → watch weatherProvider → currentLocationProvider
              │  → ensureLocationPermission() → [vào PermissionGate, xếp sau (1)]
              ▼
   postFrame: _bootstrap()
     (1) requestNotificationPermission()   ── PermissionGate ──▶ hộp thoại POST_NOTIFICATIONS
         │  (gọi TRƯỚC notif.init() để chiếm chỗ ĐẦU hàng đợi)
         └─ await notificationService.init()          [bọc try: lỗi ở đây không đứt chuỗi]
     (2) getLaunchDetails() → payload note ⇒ appRouter.push('/notes')
     (3) ensureLocationPermission()        ── PermissionGate ──▶ hộp thoại ACCESS_FINE_LOCATION
         │   (lượt của provider ở frame đầu đã xếp trước; lượt nào chạy trước thì
         │    lượt sau KIỂM TRA LẠI thấy đã cấp ⇒ KHÔNG hiện hộp thoại thứ hai)
         ▼   [từ chối → log warn, app vẫn chạy; WeatherScreen hiện PermissionDeniedWidget]
     (4) applyBackgroundTriggers()   # CHỈ ĐẾN ĐÂY mới bật FG service (kiểu `location`
         │                           # đòi quyền vị trí runtime — xem bug 11/20)
    (4b) _promptBackgroundLocationIfNeeded()   # MỜI quyền "Luôn cho phép" — MỘT LẦN
         │  hộp thoại GIẢI THÍCH trước rồi mới requestBackgroundLocation():
         │  Android 11+ KHÔNG hiện hộp thoại hệ thống mà mở thẳng trang cài đặt app,
         │  quăng người dùng vào đó không kèm lời nào thì họ không biết bấm gì.
         │  Chỉ hỏi khi đã có quyền foreground; từ chối KHÔNG chặn khởi động.
         └─ thiếu quyền này ⇒ `resolveBackgroundCoords` không bao giờ xin được fix mới
            lúc app đóng ⇒ đang đi đường mà app báo thời tiết chỗ cũ. Xem bug (28).
     (5) unawaited: scheduleDigests · scheduleAnnouncementCheck · reassertNoteNotifications
     (6) unawaited: CycleLock.runGuarded(ui, runWeatherCheck)
     (7) requestExactAlarmPermission()   # isGranted trước ⇒ Android 13+ KHÔNG mở màn cài đặt
     (8) _promptBatteryIfNeeded()        # throttle 7 ngày
     (9) _promptAutostartOnboardingIfNeeded()   # dialog 1 lần
```
⚠️ **Vì sao phải xếp hàng:** Android chỉ cho MỘT hộp thoại quyền mỗi lúc; lời gọi thứ hai bị thả im
lặng và KHÔNG có callback ⇒ future treo vĩnh viễn. Trước fix, (1) và lượt xin vị trí của provider chạy
song song bằng hai plugin khác nhau nên một trong hai bị thả → `currentLocationProvider` kẹt `loading`
→ **app trắng màn, xoay vô hạn, không hiện xin quyền vị trí** (phải vuốt tắt mở lại lần 2). Xem
`core/permissions/permission_gate.dart` và bug (19)/(20) trong `features.md`.

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
MỌI entrypoint nền (FG tick · alarm callback · WorkManager) chạy `ensureTimezoneInitialized()` ĐẦU TIÊN
— isolate nền không chạy main() nên thiếu bước này `reassertNoteNotifications` ném LateInitializationError
trên `tz.local` (nhật ký thật: 74 lỗi/24h, lịch nhắc ghi chú không bao giờ được dựng lại). Xem bug (18).

applyBackgroundTriggers() [main._bootstrap + backgroundSettingsProvider khi đổi cài đặt]:
   ⚠️ CHỈ chạy ở isolate UI. start FGS từ isolate NỀN là bất hợp pháp trên Android 12+ và
     làm SẬP TIẾN TRÌNH (plugin gọi startForeground không có try/catch) → xem "3 ĐƯỜNG BẬT LẠI".
   ▼ đọc BackgroundPrefsStore (foregroundEnabled + intervalMinutes)
   ├─ foregroundEnabled? → startWeatherForegroundService : stopWeatherForegroundService
   ├─ BackgroundScheduler.initialize   ← WorkManager LUÔN bật (lịch do JobScheduler HĐH giữ)
   └─ scheduleWeatherAlarm(firstDelayMinutes: FG bật ? interval/2 : null)  ← TÁCH PHA
       (arm alarm lệch NỬA chu kỳ để nó nằm giữa hai tick FG → backstop đúng nghĩa;
        trước đây arm liền sau khi start FG nên hai lớp tick cùng lúc mãi mãi)
main._bootstrap CÒN gọi CycleLock.runGuarded(ui, runWeatherCheck) NGAY (fire-and-forget)
   + scheduleDigests(force) + scheduleAnnouncementCheck(force) + AppLog "mở app".

BA LỚP đều gọi runWeatherCheck (isolate riêng tự dựng DI), MỖI LỚP:
   ▼ AppLog.i(src, cycle) → isWithinActiveHours?
   ├─ NGOÀI khung → không mở DB, không lấy dữ liệu
   │     • foreground_service: VẪN updateService "đang nghỉ (05:00–21:00)" (không đóng băng text cũ)
   │     • weather_alarm: chặng đêm — GHI NHẬN tình trạng FG + tự chữa lịch bản tin
   └─ TRONG khung → CycleLock.runGuarded(src, ...):     ← CHỐNG CHẠY CHỒNG (lock bằng FILE)
         không lấy được lock → AppLog "bỏ lượt: chu kỳ đang chạy bởi <chủ>", VẪN re-arm alarm
         (lock ghi TOKEN mỗi lượt chiếm; release() chỉ xoá lock của CHÍNH MÌNH — chu kỳ treo bị
          chiếm lại, tỉnh lại rồi release sẽ KHÔNG xoá lock của chủ mới)
         lấy được → MỘT AppDatabase cho cả chu kỳ:
            reassertNoteNotifications(db)  →  runWeatherCheck(source, db)  →  db.close()
  • foreground_service: onRepeatEvent mỗi intervalMinutes (5/10/15/30'), allowWakeLock,
      allowWifiLock=false
  • weather_alarm (id 2001): oneShotAt exact+allowWhileIdle, LUÔN tự re-arm dù phần trên lỗi;
      ghi mốc kế tiếp vào kWeatherAlarmNextMsKey (dòng log mang nhãn `loại: thời tiết` để LogHealth
      nhận đúng mốc bất kể lớp nào đặt); _reportForegroundServiceState CHỈ GHI NHẬN, KHÔNG start FGS
      ▼ re-arm: TRONG khung → now+interval (hoặc +5' nếu fromCacheFallback);
                NGOÀI khung → sớm hơn trong (now+kNightHopInterval 2h, nextActiveWindowStart)
                ← chặng đêm: mất một chặng chỉ mất 2h, thay vì cả đêm treo trên 1 alarm
  • WorkManager periodic (clamp ≥15', LUÔN bật, KHÔNG ràng buộc mạng): WATCHDOG —
      weatherAlarmChainStatus().overdue (mốc đã đặt trôi qua >5') → scheduleWeatherAlarm dựng lại
      chuỗi đã đứt + báo cáo tình trạng FG service.  ← bỏ NetworkType.connected vì mất mạng
      đúng là lúc watchdog cần chạy nhất
  • foreground_service tick: LƯỚI THỨ HAI cho chuỗi alarm — cũng dựng lại khi overdue
   ▼ 🔴 VÒNG ĐỜI FOREGROUND SERVICE (nguyên nhân gốc của "app đứng im 46 tiếng"):
   ▼   Android 15+ cắt FGS kiểu dataSync sau 6h tích lũy/24h (targetSdk 36) → onTimeout() mà plugin
   ▼   KHÔNG cài → HĐH dừng service. ⇒ FIX: foregroundServiceType = "location" (không bị giới hạn
   ▼   thời lượng, và đúng bản chất vì mỗi chu kỳ đều phân giải vị trí) + quyền
   ▼   FOREGROUND_SERVICE_LOCATION; startWeatherForegroundService KIỂM TRA quyền vị trí TRƯỚC khi
   ▼   start (thiếu → startForeground ném SecurityException = sập app) và ĐỌC ServiceRequestFailure.
   ▼   Khi service đã chết, isolate nền TUYỆT ĐỐI KHÔNG được start lại: nhật ký 02/08 ghi
   ▼   "thử hồi sinh" ở 12:58/13:13/13:28/13:43/14:13/14:28 rồi IM LẶNG TUYỆT ĐỐI mỗi lần
   ▼   (ForegroundServiceStartNotAllowedException ở tầng Java giết tiến trình, Dart catch không bắt
   ▼   được) → sau ~6 lần sập, HĐH force-stop app → hủy sạch alarm + job → im 46 TIẾNG.
   ▼   3 ĐƯỜNG BẬT LẠI HỢP PHÁP: (a) main.onResume → _reviveForegroundServiceOnResume (app đang
   ▼   hiển thị); (b) RestartReceiver của plugin (setAlarmClock — được HĐH miễn trừ, cần
   ▼   stopWithTask=false); (c) nút "Bật lại theo dõi liên tục" trên trang /diagnostics.
   ▼   Trong lúc chờ: ForegroundServiceHealth.markDead/deadFor + nếu im >2h trong khung giờ thì
   ▼   MỘT thông báo nhắc mở app (channel service_health, cooldown 6h). Alarm + WorkManager vẫn
   ▼   cập nhật đầy đủ, chỉ trễ hơn.
   ▼ ⚠️ Vuốt tắt app trên OEM (Nubia/MyOS…) = force-stop → hủy sạch alarm+FG; chắc chắn nhất là
   ▼    KHÓA app trong recents 🔒 (hoặc đừng vuốt tắt) + bật Tự khởi động + Không giới hạn pin.
   ▼    FG service khai báo stopWithTask=false (chỉ cứu ca task-removal, không cứu force-stop)
   ▼ ⚠️ weather_alarm RE-ARM NGAY Ở ĐẦU callback, TRƯỚC mọi việc khác — nhật ký thật cho thấy
   ▼   "06:34:03 alarm nổ" rồi tiến trình chết ngay, không kịp re-arm → chuỗi đứt 7h18.
   ▼   Arm trước = chuỗi tự duy trì; chỉ ghi đè mốc ở cuối khi fetch fail (retrySoon → 5').
runWeatherCheck(source, db) (core/background/weather_check.dart):
   resolveBackgroundCoords(source) — 3 bước, KHÔNG chỉ đọc toạ độ cũ:
      (1) getLastKnownPosition còn tươi (≤ backgroundCoordsFreshMinutes 25')? → dùng
          ← bản cũ nhận tới 24 GIỜ rồi `return` luôn ⇒ bước (2) thành CODE CHẾT, và
            `store.save()` còn đóng dấu savedAt=now cho toạ độ cũ. Fix ở bug (27);
            fix cũ hơn 25' được giữ làm lưới cuối ở (3), chọn nguồn MỚI HƠN.
      (2) toạ độ đang có cũ hơn 25' → CHỦ ĐỘNG getCurrentPosition (accuracy low, timeLimit 25s)
          ← bước MỚI: trên máy thật (1) hầu như luôn null, nên trước đây nền mãi dùng toạ độ
            từ lần MỞ APP gần nhất → di chuyển mà vẫn báo thời tiết chỗ cũ
      (3) LastLocationStore (có savedAt) làm lưới cuối
   ▼ AppLog: nguồn · toạ độ · tuổi · khoá cache · ĐỊA CHỈ ĐẦY ĐỦ (số nhà→đường→phường→quận→
   ▼   tỉnh, PlaceLabelResolver: Nominatim + cache 150m/12h + giãn cách 1'/req + fallback
   ▼   plugin geocoding) · KHOẢNG ĐÃ DỊCH CHUYỂN
   ▼ (thiếu quyền "Luôn cho phép" → log warn nói rõ, vì (2) sẽ luôn thất bại); null → dừng
   ▼  purge cache cũ: CHỈ 1 LẦN/NGÀY, trong try (trước đây mỗi chu kỳ & NGOÀI try nên một lỗi
   │  `database is locked` ở đây làm sập cả chu kỳ, bị catch(_) nuốt → mất dữ liệu + thông báo)
   ▼  GUARD QUOTA bám chu kỳ: getCachedWeather → cache tươi hơn (intervalMinutes−1') → DÙNG CACHE,
   │  KHÔNG gọi API; ngược lại getWeather → AppLog kết quả API (thời lượng / lỗi / fallback cache)
   ▼  (data.age > 45' → BỎ sinh cảnh báo, nhảy tới bước lập lịch digest)
AnalyzeRain(now) [KẾT HỢP 3 NGUỒN: quan trắc current ĐÈ nowcast khi trời đã mưa (_obsIndicatesRain);
   │ nowcast khô vẫn đối chiếu hourly (tín hiệu mạnh mm+pop≥0.6 trong cửa sổ / tiêu chí thường ngoài cửa sổ)
   │ → changeAt + rainEndsAt/duration (nối tiếp hourly khi vượt cửa sổ nowcast) + segments (đoạn cường độ)
   │ + probabilityPct] + DetectEnvChange
   ▼
   │ ⚠️ TUYÊN BỐ "đang mưa" có tiêu chí RIÊNG, chặt hơn tiêu chí "sắp mưa":
   │   _nowcastSaysRainingNow = mốc đầu ≥2.0 mm/h, HOẶC ≥0.5 mm/h DUY TRÌ 2 mốc liên tiếp.
   │   Trước đây chỉ cần >0.1 mm/h ở MỘT mốc → mưa vết lúc trời âm u bật pha raining, rồi vì
   │   cảnh báo chỉ phát khi pha ĐỔI nên app kẹt "đang mưa" >15h: vừa báo sai, vừa im lặng,
   │   vừa KHÔNG BAO GIỜ tới được rainStartingSoon (mất hẳn cảnh báo "sắp mưa").
   │   _obsIndicatesRain: mã YẾU (500 light rain, 3xx drizzle) cần rain1h>0; mã MẠNH (2xx, 501+) tin ngay.
   │ ⚠️⚠️ VÒNG 5 — chuỗi `minutely` LẤY TỪ ĐÂU (lỗi gốc vụ 10/08/2026):
   │   `/timeline/15min` của 4.0 **KHÔNG có trường `rain`** kể cả khi mưa to; nó chỉ mang
   │   `pop` + `weather[].id`. Bản cũ đọc `rain` → chuỗi nowcast ghim cứng 0.0 ở **168/168**
   │   chu kỳ suốt 2 ngày (kể cả 37 chu kỳ `current` báo mã 500 kèm mưa đo được) → pha luôn
   │   `dry`. Vì nowcast vừa là nguồn CHÍNH vừa có quyền PHỦ QUYẾT quan trắc, app mù hẳn với
   │   mưa nhỏ. ⇒ `WeatherRemoteDataSource.precipFromCondition` suy mm/h từ `weather[].id`.
   │   `nowcastDeniesRain` nay QUÉT THẬT cả cửa sổ (không dùng xấp xỉ `phase == dry`, vốn vẫn
   │   `true` khi nowcast đang báo 0.1–0.49 mm/h ⇒ nowcast THẤY MƯA mà vẫn phủ quyết).
   │   ⚠️ KHÔNG nới van khi nowcast toàn 0: nowcast CHẠY ĐÚNG và chắc chắn khô cũng cho toàn 0
   │   — không phân biệt được bằng giá trị; nới sẽ hồi sinh bug (14)/(21). Chống bằng PHÁT HIỆN:
   │   log `warn` "NGHI VẤN nowcast" khi nowcast phẳng lì 0 mà `current.rain1h > 0`.
   │   ⚠️ rain1h là số TÍCH LŨY 1 GIỜ nên còn dư ~1h SAU KHI mưa tạnh (OWM vẫn giữ mã 500):
   │   nhật ký 01/08 `nowcast 0.00 · rain1h 0.74 · mã 500` → app báo "đang mưa 80%" lúc trời đã
   │   tạnh, rồi KẸT pha raining = im lặng. ⇒ nowcastSawNoRainAtAll (nowcast có dữ liệu và kết
   │   luận dry cả cửa sổ) thì NOWCAST THẮNG. Van HẸP: KHÔNG chặn mã mạnh, KHÔNG chặn
   │   rain1h ≥ 2.0mm, KHÔNG chặn khi nowcast thấy mưa sắp tới (nowcast chỉ TRỄ, không phủ định).
   ▼ AppLog.i(analyze): pha + tình hình + nguồn + SỐ LIỆU THÔ (nowcast bây giờ, ngưỡng đang áp,
   │ mưa 1h quan trắc, mã OWM, tuổi dữ liệu) + mốc + giờ tạnh + xác suất
AlertStateStore.read()  ← LUÔN prefs.reload() (SharedPreferences cache RIÊNG từng isolate; isolate
   │ FG sống hàng giờ nên không reload thì không bao giờ thấy trạng thái isolate alarm ghi → báo lặp)
   ▼ HẾT HẠN sau AlertStateStore.maxAge=2h → trả về như CHƯA CÓ GÌ (khởi đầu mới) + log warn.
   │ Chống-spam giả định các chu kỳ nối tiếp vài phút; app bị giết hàng giờ thì giả định sụp —
   │ nhật ký thật: 12:24 hôm sau vẫn so với trạng thái ghi từ 20:57 hôm trước.
   ▼ cả chuỗi read → show → write nằm TRONG CycleLock (không thì 2 isolate cùng đọc state cũ,
   │ cùng show → 1 thẻ nhưng 2 lần heads-up + 2 lần âm thanh)
BuildWeatherAlerts(rain, env, previousPhase + previousChangeAt + previousNotifiedAt từ AlertStateStore)
   │ chỉ sinh alert khi PHA đổi; NGOẠI LỆ khi pha giữ nguyên:
   │  (a) changeAt lệch so lần ĐÃ BÁO: SỚM ≥15' / MUỘN ≥45' (bất đối xứng) → "Cập nhật:" (cùng ID)
   │  (b) đã báo từ XA (>35'), onset áp sát còn ≤35' → nhắc "Sắp mưa: còn ~N phút" (một lần)
   │ KHỞI ĐẦU MỚI (previousCategory == null vì state hết hạn / lần chạy đầu): chỉ báo TÌNH HÌNH khi
   │ WeatherSeverity ≥ notice (mưa/dông/sương mù). Trước đây luôn báo → mỗi lần app hồi sinh sau
   │ khoảng đứt lại phát "🌤️ Nhiều mây" vô ích (chiếm phần lớn thông báo trong ngày).
   │ nội dung mưa: giờ bắt đầu (HH:MM từ changeAt) + % + giờ tạnh/thời lượng (rainEndsAt)
   │  + "Diễn biến: mưa vừa ~17:00–19:00, sau đó mưa nhỏ..." (describeRainCourse khi ≥2 đoạn)
   ▼
   │ `_rainClaimUnsupportedReason` trả LÝ DO (không còn bool) → weather_check ghi dòng `skip`
   │ nói thẳng cảnh báo nào bị nuốt + số liệu thô. Xác thực nhóm mưa nhẹ/vừa nay chỉ cần
   │ **lượng mưa đo được > 0** (ngưỡng cũ ≥0.5 đã nuốt CẢ DẢI mưa nhẹ thật 0.10–0.36 mm).
   ▼
NotificationService.show(id cố định) → AppLog.i(notify, "ĐÃ BÁO: <tiêu đề>" + id + nội dung)
   │ (không có alert nào → AppLog.i(skip, "chưa có gì đổi" + pha trước/nay + mốc đã báo + báo lúc))
   ▼
AlertStateStore.write(phase + changeAt/notifiedAt — CHỈ chốt mốc mới khi thật sự phát thông báo
   │ mưa, tránh drift nuốt ngưỡng "Cập nhật")
   ▼ (foreground service còn updateService: thông báo thường trực live nhiệt độ + tình hình)
NotificationPrefsStore.read() → scheduleDigests(prefs, source)         ┐ đều qua AlarmScheduleGuard
AnnouncementPrefsStore.read() → scheduleAnnouncementCheck(ap, source)  ┘ (throttle 1h + justPassed)
   ▼ mọi bước trên: catch (e, st) → AppLog.e  (KHÔNG còn catch(_) nuốt trần)
   ▼ finally: ApiClient.close() (không đóng thì mỗi chu kỳ rò một HttpClient + pool socket)
```

### 2e. Nhật ký hoạt động — ghi ở mọi isolate, đọc ở trang /diagnostics
```
[GHI] mọi lớp nền + main isolate:
   AppLog.i/w/e(source, tag, message, {data})   ← static, không Riverpod, dùng được ở MỌI isolate
   ▼ _queue (chuỗi hoá trong cùng isolate) → _rotateIfNeeded (>512KB → dồn sang kato.1.log)
   ▼ File(<appDocs>/logs/kato.log).writeAsString(mode: writeOnlyAppend, flush: true)
   ▼ KHÔNG dùng Drift — chủ ý: nhật ký phải ghi được ĐÚNG LÚC DB bị khoá (chính là lỗi cần truy),
   │  và append file cho nhiều isolate ghi song song mà không cần phối hợp lock
   ▼ mọi lỗi I/O bị nuốt tại đây (chỗ DUY NHẤT được phép) — ghi log không được làm hỏng chu kỳ
   ▼ isolate nền kết thúc → AppLog.flush() để không mất dòng cuối

[ĐỌC] SettingsScreen → "Nhật ký hoạt động" → context.push('/diagnostics')
   ▼
DiagnosticsScreen → logEntriesProvider → AppLog.readAll()
   │  đọc kato.1.log rồi kato.log → LogEntry.tryParse từng dòng (dòng hỏng → BỎ, không sập trang)
   │  → bỏ dòng > logRetentionDays(7) → sort mới-nhất-trước → cắt còn logMaxEntries(5000)
   ├─ logHealthProvider → LogHealth.from(entries): lastCycle/lastFetchOk/lastNotify/nextAlarm
   │     + thống kê 24h + longestGap24h (bỏ đoạn đầu cửa sổ nếu nhật ký chưa trải hết 24h)
   ├─ runtimeStatusProvider → BackgroundPrefsStore + isRunningService + canScheduleExactAlarms
   │     + isIgnoringBatteryOptimizations  → thẻ "Cấu hình & quyền"
   └─ filteredLogEntriesProvider ← logFilterProvider (Tất cả/Chạy nền/Thông báo/Lỗi) + logSearchProvider
   ▼ list nhóm theo ngày, màu theo mức · "Copy toàn bộ" (AppLog.exportText → Clipboard) · "Xoá nhật ký"
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
   └─ id >= digestBase → ⚠️ RE-ARM NGÀY MAI NGAY (_rearmTomorrow) TRƯỚC khi làm gì khác
        (isolate có thể bị giết giữa chu kỳ; không đọc được prefs thì re-arm bằng mốc mặc định
         — thà bản tin lệch giờ hơn là chuỗi im lặng mãi)
        → index = id − digestBase → resolveBackgroundCoords → **CycleLock.runWaiting** (CHỜ lock
          rồi chạy bất chấp — runGuarded từng BỎ RƠI bản tin: nổ đúng lúc WorkManager giữ lock →
          bỏ lượt → tự hẹn lại NGÀY MAI = mất hẳn bản tin của ngày đó) → getWeather → BuildDailyDigest
        (BuildRainOutlook mưa theo buổi + UvAdvice lời khuyên UV theo mức)
        → NotificationService.show(id)   ← DỮ LIỆU TƯƠI
        → RE-ARM: scheduleDigestSlot(id, times[index]) cho NGÀY MAI (vẫn re-arm khi thiếu vị trí/offline;
          KHÔNG re-arm nếu index đã bị xóa hoặc !enabled)

TỰ CHẨN ĐOÁN: DigestSettingsCard "Đặt bản tin thử sau 1 phút" → scheduleDigestTest → oneShotAt(now+1',
   digestTest). Nổ khi khóa màn hình = lập lịch OK; vuốt tắt app rồi KHÔNG nổ = force-stop OEM → bật Autostart.
```

### 2c. Theo dõi thông báo (JLPT/MBA) — backend crawl + mobile poll 1 lần/ngày
```
[BACKEND] cron/HTTP: python -m app.jobs.daily_crawl  |  POST /api/v1/crawl
   ▼ crawl_service.run_all: với mỗi watch_source (whitelist nguồn GỐC chính thức)
      httpx.get(bytes) → BeautifulSoup parse (item_selector) → mỗi mục:
        content_hash = sha256(topic|title|url) → ĐÃ có trong DB? → bỏ (không phải tin MỚI)
        verify_service.verify(topic,title,text): có ANTHROPIC_API_KEY → Claude Haiku {matched,score,summary}
                                                 không key → rule-based (keyword topic + regex ngày; MBA cờ "không GMAT")
        matched? → lưu Announcement(source_domain để kiểm chứng, verified=score≥0.5)
   ▼ GET /api/v1/announcements?topic=&since=  ← mobile tiêu thụ

[MOBILE] lập lịch (idempotent): runWeatherCheck (cạnh scheduleDigests) / mở app / đổi cài đặt (force)
   ▼ scheduleAnnouncementCheck(prefs, {force}) → AlarmScheduleGuard.claimSchedule (throttle 1h,
   │   có prefs.reload) + justPassed (mốc vừa qua ≤20' → để callback tự re-arm, đừng dời sang mai)
   │   ⚠️ trước đây thiếu CẢ HAI guard này dù bị gọi mỗi chu kỳ → cancel đua với re-arm từ isolate alarm
   ▼ oneShotAt(announcementAlarm=1200) exact+allowWhileIdle (KHÔNG periodic)
Đến mốc giờ → AlarmManager đánh thức isolate → announcementCheckCallback(id)
   → ⚠️ RE-ARM NGÀY MAI NGAY, TRƯỚC khi làm gì khác (isolate có thể bị giết giữa chu kỳ)
   → CycleLock.runWaiting(announce, _fetchAndNotify):  ← CHỜ lock rồi chạy bất chấp; mỗi ngày chỉ
        có MỘT lượt poll nên bỏ lượt là mất tin cả ngày (runGuarded từng bỏ vì WorkManager giữ lock)
   AnnouncementRepository.fetchNewUnseen(topics): fetch backend → lọc bỏ contentHash có trong Drift seen_announcements
   → markSeen(fresh) TRƯỚC (một lượt ghi cho cả lô)
        ⚠️ THỨ TỰ QUAN TRỌNG: trước đây show TRƯỚC rồi mới markSeen — lượt ghi thất bại (DB bị isolate
        khác khoá) thì tin đã hiện mà không được ghi nhận → lượt poll sau BÁO LẠI đúng tin đó
   → mỗi tin: NotificationService.showAnnouncement (KatoVoice.announcement + domain nguồn,
        id = announcementBase + BỘ ĐẾM XOAY VÒNG (không còn remoteId%500 làm hai tin đè nhau),
        payload announcement:<id>)
   → show lỗi → unmarkSeen(failed) BÙ TRỪ để lượt sau thử lại
   → RE-ARM: scheduleAnnouncementSlot(id, checkMinutes) cho NGÀY MAI (finally; bỏ nếu !enabled)
Chạm thông báo → onNotificationTap(payload announcement:) → appRouter.push('/announcements')
   ▼ crawl_service cũng set extracted_dates = date_extract.extract_dates(text) (regex, gợi ý "chưa kiểm chứng")
TỰ CHẨN ĐOÁN: AnnouncementsScreen "Kiểm tra tin mới ngay" → checkAnnouncementsNow (KHÔNG re-arm) → snackbar số tin.
```

### 2d. Lịch & mốc hạn (đăng ký/thi/kết quả) — độ chính xác 3 tầng, KHÔNG LLM
```
[BACKEND] seed_events (idempotent upsert_by_label) → exam_events curated=true (JLPT kỳ 7&12/2026,
          ngày xác thực từ info.jees-jlpt.jp)  ▼ GET /api/v1/events?topic=  ← mobile tiêu thụ
[MOBILE] AnnouncementsScreen section "📅 Lịch & hạn":
   examEventsProvider → EventRepository.fetchMerged(topics):
      backend events (ExamEvent.fromJson)  +  Drift event_overrides (bản sửa/thêm của người dùng)
      → áp override theo sourceEventId (bản sửa LUÔN ưu tiên, isUserVerified) / ghép event tự thêm
   → mỗi event: computeStatus(event, now) → EventStatus{summaryLabel, level, lines}
      chip màu đỏ/cam/xanh/xám: đăng ký chưa mở/đang mở(còn N)/hết hạn · sắp thi(còn N)/đã thi · kết quả
   Sửa/Thêm: EventEditDialog (4 date-picker, dựng tường minh cho phép xoá về null)
      → EventRepository.saveOverride (upsert theo sourceEventId / overrideId) → ref.invalidate(examEventsProvider)
      "Khôi phục lịch gốc"/"Xoá" → deleteOverride(overrideId)
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
