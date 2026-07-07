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
- **Mobile:** entities `Coordinates`, `Place` (+ `thoroughfare` đường/phố, `subAdministrativeArea`) · `LocationDataSource` (geolocator + geocoding) · **`NominatimDataSource`** (reverse geocode OSM) · `LocationRepositoryImpl` · `LastLocationStore` (SharedPreferences) · providers `currentLocationProvider` (Future), `locationStreamProvider` (Stream), `currentPlaceProvider` (Future<Place?>), `nominatimDataSourceProvider` (DI)
- **Key logic:** `PermissionService.ensureLocationPermission` xử lý denied/deniedForever; `distanceFilter=200m` (AppConfig) để tiết kiệm pin; trả `Either<Failure, Coordinates>`. **Reverse geocoding (2 tầng):** `getPlace` **ưu tiên Nominatim** (`NominatimDataSource` → OSM `/reverse`, `accept-language=vi`, User-Agent OSM) để lấy địa chỉ VN chi tiết **đường → phường → quận → thành phố**; chỉ nhận khi có ≥1 cấp dưới tỉnh/thành, ngược lại **fallback plugin `geocoding`** (chạy offline nhưng ở VN thường chỉ trả tỉnh/thành). Kết quả gói vào `Place` với `shortLabel` (phường/quận → tỉnh, cho AppBar) **và `fullLabel`** (gộp đường → phường → quận → `subAdministrativeArea` → tỉnh, bỏ trùng, KHÔNG cắt — hiển thị ở header thân màn hình, giúp kiểm chứng app đang lấy đúng vị trí). Lỗi mạng/không có dịch vụ → null (không chặn UI thời tiết). **`LastLocationStore`**: `currentLocationProvider` lưu toạ độ mỗi lần định vị thành công để background isolate (`resolveBackgroundCoords`) fallback khi `getLastKnownPosition` null/quá cũ (>24h) — bảo đảm worker/bản tin vẫn fetch qua đêm khi máy đứng yên.

### Giao diện & cá nhân hóa (theme)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `core/theme/` — `theme_palettes.dart` (`AppPalette` + `kAppPalettes`), `weather_theme.dart` (`seedForCategory`), `app_theme.dart` (`buildAppTheme`), `theme_controller.dart` (`ThemeSettings` + `ThemeController` StateNotifier, provider `themeControllerProvider`) · màn `SettingsScreen` (`features/settings/`)
- **Key logic:** 4 mức gộp 1 hệ thống — Sáng/Tối/Hệ thống (`ThemeMode`), bảng màu chọn sẵn (seed), Material You (`dynamic_color` `DynamicColorBuilder`), đổi màu theo thời tiết. **Precedence seed** (tính ở `main.dart`): weatherAdaptive (theo `weatherConditionProvider`) > useDynamicColor (corePalette hệ thống) > paletteId. Cài đặt lưu/đọc SharedPreferences. Settings còn có trạng thái quyền thông báo, công tắc **"Theo dõi thời tiết liên tục"** (`backgroundSettingsProvider` bật/tắt foreground service) + guide whitelist pin (`requestIgnoreBatteryOptimizations`, có `isIgnoringBatteryOptimizations` để nhắc lại).

### Thời tiết (weather)
- **Status:** ✅ done
- **Backend:** — (gọi thẳng OpenWeatherMap **One Call 4.0**)
- **Mobile:** entities `WeatherData/CurrentWeather/MinutelyForecast/HourlyForecast/RainStatus/WeatherCondition` · `WeatherMapper` (JSON→entity) · `WeatherRemoteDataSource` (Dio, 4.0 adapter) · `WeatherLocalDataSource` (Drift) · `WeatherRepositoryImpl` (+ `getCachedWeather`) · usecases `AnalyzeRain`, `DetectEnvChange` · providers `weatherProvider` (StreamProvider), `connectivityStatusProvider`, `rainStatusProvider`, `weatherConditionProvider` · screen `WeatherScreen` + widgets (current_card, condition_card, hourly_list, rain_alert_banner)
- **Key logic:** **4.0 adapter** — `WeatherRemoteDataSource` gọi song song `/onecall/current` + `/timeline/15min` + `/timeline/1h`, chuẩn hoá về shape gộp (current+minutely+hourly) nên `WeatherMapper`/cache/repo không đổi. **Stale-while-revalidate**: `weatherProvider` (StreamProvider) phát cache ngay (`getCachedWeather`, không gọi mạng) rồi mới gọi API NẾU thiếu cache hoặc cache `needsRevalidate` (≥`weatherRevalidateMinutes`=15'); fetch lỗi mà có cache → giữ cache. `currentLocation` ưu tiên last-known → mở app nhanh, và **lưu toạ độ vào `LastLocationStore`** để background dùng khi last-known hết hạn. `AppLifecycleListener` (main) làm mới khi resume. Badge "dữ liệu cũ" dùng `connectivityStatusProvider` để nói đúng offline vs đang làm mới. **`AnalyzeRain`** nhận `now` (test được), **neo mọi phép tính vào `now` thật**: lọc bỏ điểm dự báo quá khứ (minutely quá cũ >15' so với now → fallback hourly; hourly giữ giờ có khối còn giao hiện tại), trả **`changeAt` (timestamp tuyệt đối của chuyển biến)** + `minutesUntilChange` = phút từ now (clamp ≥0, hết lỗi "14:50 báo 60' dù mưa 15:00"); chống nhiễu `dryStreakToConfirmStop=3`; guard tầm nhìn `rainSoonHorizonMinutes=120'` theo phút thực; ngưỡng pop hourly `rainAlertPopThreshold=0.5` (AppConfig). **`rainEndsAt`/`durationMinutes`** (mưa kéo dài đến bao giờ): pha `rainStartingSoon` quét tiếp từ mốc bắt đầu mưa tìm điểm "khô bền vững" (`_minutelyRainEnd`/`_hourlyRainEnd`) → giờ tạnh + thời lượng; null nếu mưa kéo dài quá tầm dự báo. **`probabilityPct`** = pop của **giờ chứa `changeAt`** (so timestamp, không chia 60), **fallback pop của giờ gần nhất** khi không có giờ chứa đúng eventTime → hiếm khi rỗng; floor `minutelyProbabilityFloorPct=80%` khi minutely đã xác nhận mưa/sắp mưa; chỉ gán cho pha startingSoon/raining (dry/stoppingSoon → null). **UI thời tiết mở rộng:** header địa điểm `Place.fullLabel` đầy đủ; `CurrentWeatherCard` nhận thêm `hourly` → hi/lo 24h + UV kèm band màu (`UvAdvice`) + mây%; **`AdvisoryCard`** ("Lưu ý hôm nay") render danh sách từ **`BuildAdvisories`** (gom tình hình + UV + độ ẩm cao/thấp + gió mạnh + mưa). **`BuildRainOutlook`** quét `hourly` cả ngày, **4 buổi Đêm(0–5)/Sáng(5–11)/Chiều(11–17)/Tối(17–24) phủ đủ 24h**; các giờ ướt liền kề (≤1h) gom thành **từng đợt riêng** (không gộp 2 đợt cách xa thành 1 khung dài), >2 đợt/buổi → "rải rác nhiều đợt" (ngưỡng `rainOutlookPopThreshold`=0.4). Parser JSON thủ công guard null.

### Phân loại tình hình thời tiết (weather condition)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** entity `WeatherCondition` (+ enum `WeatherCategory`, `WeatherSeverity`) · `WeatherCondition.classify(id, rainMmH)` · provider `weatherConditionProvider` · widget `ConditionCard`. `CurrentWeather.conditionId` parse từ `weather[0].id`.
- **Key logic:** map mã OWM → nắng/ít mây/nhiều mây/u ám/sương mù/mưa nhỏ-vừa-to-rất to/dông/bão lớn/lốc xoáy/tuyết, kèm nhãn VI + lời khuyên + mức độ (info/notice/warning/severe). Lượng mưa lớn có thể nâng cấp cường độ (vd 500 + rainMmH≥2.5 → mưa to).

### Thông báo thông minh (alerts)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `WeatherAlert` · `BuildWeatherAlerts` (usecase) · `AlertStateStore` (SharedPreferences) · `NotificationService` (core/notifications, `show` + `scheduleDaily`/`cancel`) · **LÕI `runWeatherCheck`** (`core/background/weather_check.dart`) · **`applyBackgroundTriggers`** (`core/background/background_triggers.dart`) · `BackgroundScheduler` + `callbackDispatcher` (WorkManager) · `foreground_service.dart` (`flutter_foreground_task`) · `weather_alarm.dart` (alarm exact) · `BackgroundPrefsStore` + `backgroundSettingsProvider`
- **Key logic:** `applyBackgroundTriggers` (gọi ở `main._bootstrap` + khi đổi cài đặt nền): FG **bật** (mặc định) → `startWeatherForegroundService` **+ `scheduleWeatherAlarm` chạy SONG SONG làm BACKSTOP** (hồi phục khi FG bị Doze/OEM giết mà chưa force-stop), hủy WorkManager; FG **tắt** → `stopWeatherForegroundService` + alarm exact + WorkManager. **Foreground service** — thông báo thường trực (channel `weather_foreground` LOW) live `foregroundStatusText` (emoji + °C + tình hình + UV + **giờ HH:mm**), chu kỳ = `intervalMinutes` prefs (5/10/15/30'), **`allowWifiLock=false`** + `allowWakeLock`; `_tick` **re-assert ghim ghi chú** TRƯỚC rồi `runWeatherCheck`. **Alarm exact** (`kWeatherAlarmId=2001`) **luôn tự re-arm** (backstop thường trực); `_run` cũng re-assert notes. **WorkManager** clamp **≥15'**. **GUARD QUOTA bám chu kỳ:** chỉ gọi API khi cache cũ ≥ `intervalMinutes − 1'` → khử API trùng giữa FG tick và alarm nên backstop thêm ít nhiệt. **Mở app chạy `runWeatherCheck` ngay** (`main._bootstrap`, fire-and-forget) → khởi tạo `AlertStateStore` + cảnh báo tức thì + làm tươi thông báo thường trực. **Guard dữ liệu cũ:** bỏ cảnh báo nếu `data.age > alertMaxDataAgeMinutes=45'`. Sinh **3 nhóm** (mưa/tình hình/môi trường), chống spam: chỉ phát khi PHA/NHÓM đổi so với `AlertStateStore` — ngoại lệ `changeAt` lệch ≥15' → "Cập nhật:". Nội dung mưa kèm **giờ + % + giờ tạnh/thời lượng**. `RainAlertBanner` hiển thị cùng nội dung (độc lập đổi pha). ⚠️ **Force-stop OEM khi vuốt app** (Nubia/MyOS, Xiaomi…) hủy sạch alarm → cần bật **Tự khởi động + Không giới hạn pin** (onboarding + `MainActivity` MethodChannel `katocast/oem` deep-link Autostart đa-hãng).

### Bản tin thời tiết hằng ngày (daily digest)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `DailyDigest` + `BuildDailyDigest` (usecase, nhận `now` để test) · `BuildRainOutlook` (usecase mưa cả ngày) · `NotificationPrefsStore` + `DigestPrefs` **{enabled, List<int> times}** (SharedPreferences, `setStringList`) · `scheduleDigests`/`scheduleDigestSlot`/`canScheduleExactAlarms` (`digest_scheduler.dart`) · `digestAlarmCallback` (`core/background/digest_alarm.dart`) · `NotificationSettingsController` (`addTime`/`removeTime`/`updateTime`) + provider `notificationSettingsProvider` · UI **`DigestSettingsCard`** trong **`WeatherScreen`** (dưới HourlyList) · lập lịch qua **`android_alarm_manager_plus`** (dải ID động `NotificationIds.digestBase=1100 + index`, tối đa `AppConfig.digestMaxSlots=64`)
- **Key logic:** kênh thông báo **độc lập** với cảnh báo sự kiện — tóm tắt nhiệt độ + cảm giác như + hi/lo 24h + tình hình `WeatherCondition` + lời khuyên + **outlook mưa CẢ NGÀY theo buổi** (`BuildRainOutlook`) + gợi ý mưa tức thời từ `AnalyzeRain` (giờ HH:MM từ `changeAt` + % + **giờ tạnh**) + **UV kèm lời khuyên theo mức** (`UvAdvice`) + "Cập nhật lúc HH:MM". **NHIỀU MỐC GIỜ TÙY Ý:** `DigestPrefs.times` (List phút-trong-ngày, sort+dedupe qua `normalizeTimes`, kẹp ≤ `digestMaxSlots`); người dùng thêm/xóa trong `DigestSettingsCard` ở màn Thời tiết (bê từ Settings sang); **migrate** tự động từ key cũ `digest_morning_min`/`digest_evening_min` → `digest_times` khi đọc lần đầu. Mỗi mốc index `i` → alarm ID `digestBase + i`; `digestAlarmCallback` giải mã `index = id − digestBase`, hiển thị rồi **re-arm cùng id** với `times[index]` (không re-arm nếu index đã bị xóa/`!enabled`). **Cơ chế = `AndroidAlarmManager.oneShotAt`** (`wakeup + allowWhileIdle + rescheduleOnReboot`) — KHÔNG dùng `periodic` (setRepeating INEXACT bị Doze hoãn → bản tin sáng không nổ). **FIX quyền exact:** `scheduleDigestSlot` kiểm tra `canScheduleExactAlarms`; **thiếu quyền → `exact:false`** (inexact, vẫn nổ gần đúng thay vì `SecurityException` im lặng) + cảnh báo; `main._bootstrap` **xin `requestExactAlarmPermission` lúc khởi động**; `DigestSettingsCard` có dòng cảnh báo + nút xin quyền. `scheduleDigests` **idempotent** → gọi ở `_bootstrap`, controller, `runWeatherCheck` (mỗi chu kỳ) **tự chữa** chuỗi đứt. **NÚT TỰ CHẨN ĐOÁN** "Đặt bản tin thử sau 1 phút" (`scheduleDigestTest` → alarm với `NotificationIds.digestTest=1099` < digestBase; `digestAlarmCallback` nhận diện id này → `_runDigestTest` hiện thông báo xác nhận, KHÔNG fetch/re-arm) → phân biệt lỗi lập lịch vs **force-stop OEM khi vuốt app** (chỉ khắc phục bằng bật Tự khởi động + Không giới hạn pin). Tại mốc giờ, callback (isolate riêng) **FETCH dữ liệu tươi rồi hiển thị**. **AndroidManifest** khai báo `USE_EXACT_ALARM`/`SCHEDULE_EXACT_ALARM`.

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

### Ghi chú (notes)
- **Status:** ✅ done
- **Backend:** — (client-only, Drift + notification cục bộ)
- **Mobile:** entities `Note`/`NoteItem`/`NoteRepeat` (`features/notes/domain`) · `NoteLocalDataSource` (Drift CRUD, transaction cho items/delete) · `note_notification_service.dart` (hằng/hàm thuần: `noteSlotId`, `buildReminderSlots`, `buildPinnedBody`, `notePayload`; class `NoteNotificationService.sync/cancelAll/syncReminders/showPinned`; `reassertNoteNotifications`) · `core/notifications/notification_response_handler.dart` (tap + action nền) · providers `noteLocalDataSourceProvider`, `noteNotificationServiceProvider`, `notesControllerProvider` · screens `NotesScreen` (`/notes`), `NoteEditScreen` (`/notes/edit`) · widget `note_colors`
- **Key logic:** Note = text (+ checklist tick trong app, màu, tìm kiếm in-memory, khu "Đã xong"). **Ghim sticky:** notification `ongoing + autoCancel:false + onlyAlertOnce` trên channel riêng `note_pinned` (Importance.low — im lặng), sống qua "Xoá tất cả"; chỉ gỡ qua nút action **"Đã đọc"** (`cancelNotification: true, showsUserInterface: false` — cần `ActionBroadcastReceiver` trong AndroidManifest) → handler nền (isolate riêng, tự init tz + `AppDatabase()`) set `pinned=false` **note giữ nguyên trong app**; Android 14 vuốt gỡ được ongoing → **re-assert** ở `main._bootstrap` + đầu chu kỳ WorkManager 15' (`_reassertNotes`, chạy TRƯỚC weather check nên không bị guard vị trí chặn). **Hẹn nhắc:** `zonedSchedule` exact (fallback inexact khi bị thu hồi quyền) — một lần (slot 8, không lập nếu quá khứ) / hằng ngày (slot 8 + `DateTimeComponents.time`) / hằng tuần theo thứ (slot 1..7 + `dayOfWeekAndTime`, mỗi thứ một lịch); note đang ghim → bản nhắc cũng sticky + có "Đã đọc"; **"Đã đọc" không giết alarm lặp** (chỉ cancel slot 0 + re-sync 1..8 — `plugin.cancel` Dart mới huỷ alarm). **ID scheme:** `10000 + noteId*16 + slot` (0=ghim, 1..7=thứ, 8=ngày/một lần) — không đụng dải weather 1001–1006. **Mọi mutation qua phễu `sync()`** (cancelAll 9 slot → dựng lại) tránh sticky bị "bake" vào lịch cũ. Main isolate không thấy write từ isolate action → `ref.invalidate(notesControllerProvider)` khi resume. DB v2 (`MigrationStrategy` v1→v2, row class `NoteRow`/`NoteItemRow` qua `@DataClassName`).

---

## Database Tables Status

> DB cục bộ Drift (`mobile/lib/core/database/app_database.dart`), schemaVersion = **2** (có `MigrationStrategy` tường minh).

| Table | Status | Migration | Ghi chú |
|-------|--------|-----------|---------|
| `weather_cache` | ✅ | Drift v1 | cache JSON One Call theo locationKey |
| `fixed_route_points` | ✅ | Drift v1 | lộ trình cố định (Module 2) |
| `notes` | ✅ | Drift v2 | ghi chú (row class `NoteRow`); pinned/done/remindAt/repeat/weekdaysMask |
| `note_items` | ✅ | Drift v2 | checklist của note (row class `NoteItemRow`), gom theo noteId + seq |

---

## Mobile Providers — State Map

| Provider | Loại | Feature | Watch / phụ thuộc |
|----------|------|---------|-------------------|
| `currentLocationProvider` | FutureProvider | location | `locationRepositoryProvider` |
| `locationStreamProvider` | StreamProvider | location | `locationRepositoryProvider` |
| `currentPlaceProvider` | FutureProvider | location | `currentLocationProvider` + `locationRepositoryProvider` (Nominatim → fallback geocoding) |
| `themeControllerProvider` | StateNotifierProvider | theme | SharedPreferences; UI Settings + `main.dart` |
| `notificationSettingsProvider` | StateNotifierProvider | alerts (digest) | `NotificationPrefsStore` (SharedPreferences); state `DigestPrefs {enabled, List<int> times}`; UI `DigestSettingsCard` ở màn Weather → add/remove/updateTime + `scheduleDigests` |
| `backgroundSettingsProvider` | StateNotifierProvider | background (FG + chu kỳ) | `BackgroundPrefsStore`; state `BackgroundSettings {foregroundEnabled, intervalMinutes}`; UI Settings → `applyBackgroundTriggers` (start/stop FG, hủy/đặt alarm+WorkManager) |
| `routeControllerProvider` | StateNotifierProvider | fixed_route | `poiRepositoryProvider` (Drift + Overpass) |
| `notesControllerProvider` | StateNotifierProvider | notes | `noteLocalDataSourceProvider` (Drift) + `noteNotificationServiceProvider` |
| `poiRepositoryProvider` | Provider (DI) | fixed_route | `routeLocalDataSourceProvider` + `overpassDataSourceProvider` |
| `newsProvider` | FutureProvider | map_news | `currentLocationProvider` + `newsRepositoryProvider` (RSS) |
| `weatherProvider` | FutureProvider | weather | `currentLocationProvider` + `weatherRepositoryProvider` |
| `rainStatusProvider` | Provider | weather | `weatherProvider` |
| `weatherConditionProvider` | Provider | weather | `weatherProvider` |
| `*RepositoryProvider`, `*DataSourceProvider` | Provider (DI) | location/weather | hạ tầng ở `core/di/providers.dart` |

> Loại: `FutureProvider` (read) · `StateNotifierProvider` (mutation) · `StreamProvider` · `Provider`.
