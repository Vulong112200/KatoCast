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
- **Key logic:** **4.0 adapter** — `WeatherRemoteDataSource` gọi song song `/onecall/current` + `/timeline/15min` + `/timeline/1h`, chuẩn hoá về shape gộp (current+minutely+hourly) nên `WeatherMapper`/cache/repo không đổi. **Stale-while-revalidate**: `weatherProvider` (StreamProvider) phát cache ngay (`getCachedWeather`, không gọi mạng) rồi mới gọi API NẾU thiếu cache hoặc cache `needsRevalidate` (≥`weatherRevalidateMinutes`=15'); fetch lỗi mà có cache → giữ cache. `currentLocation` ưu tiên last-known → mở app nhanh, và **lưu toạ độ vào `LastLocationStore`** để background dùng khi last-known hết hạn. `AppLifecycleListener` (main) làm mới khi resume. Badge "dữ liệu cũ" dùng `connectivityStatusProvider` để nói đúng offline vs đang làm mới. **`AnalyzeRain`** nhận `now` (test được), **neo mọi phép tính vào `now` thật**: lọc bỏ điểm dự báo quá khứ (minutely quá cũ >15' so với now → fallback hourly; hourly giữ giờ có khối còn giao hiện tại), trả **`changeAt` (timestamp tuyệt đối của chuyển biến)** + `minutesUntilChange` = phút từ now (clamp ≥0, hết lỗi "14:50 báo 60' dù mưa 15:00"); chống nhiễu `dryStreakToConfirmStop=3`; guard tầm nhìn `rainSoonHorizonMinutes=120'` theo phút thực; ngưỡng pop hourly `rainAlertPopThreshold=0.5` (AppConfig). **`probabilityPct`** = pop của **giờ chứa `changeAt`** (so timestamp, không chia 60), floor `minutelyProbabilityFloorPct=80%` khi minutely đã xác nhận mưa/sắp mưa (tránh "đang mưa, khả năng 40%"); chỉ gán cho pha startingSoon/raining (dry/stoppingSoon → null). **`BuildRainOutlook`** quét `hourly` cả ngày, **4 buổi Đêm(0–5)/Sáng(5–11)/Chiều(11–17)/Tối(17–24) phủ đủ 24h**; các giờ ướt liền kề (≤1h) gom thành **từng đợt riêng** (không gộp 2 đợt cách xa thành 1 khung dài), >2 đợt/buổi → "rải rác nhiều đợt" (ngưỡng `rainOutlookPopThreshold`=0.4). Parser JSON thủ công guard null.

### Phân loại tình hình thời tiết (weather condition)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** entity `WeatherCondition` (+ enum `WeatherCategory`, `WeatherSeverity`) · `WeatherCondition.classify(id, rainMmH)` · provider `weatherConditionProvider` · widget `ConditionCard`. `CurrentWeather.conditionId` parse từ `weather[0].id`.
- **Key logic:** map mã OWM → nắng/ít mây/nhiều mây/u ám/sương mù/mưa nhỏ-vừa-to-rất to/dông/bão lớn/lốc xoáy/tuyết, kèm nhãn VI + lời khuyên + mức độ (info/notice/warning/severe). Lượng mưa lớn có thể nâng cấp cường độ (vd 500 + rainMmH≥2.5 → mưa to).

### Thông báo thông minh (alerts)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `WeatherAlert` · `BuildWeatherAlerts` (usecase) · `AlertStateStore` (SharedPreferences) · `NotificationService` (core/notifications, `show` + `scheduleDaily`/`cancel`) · `BackgroundScheduler` + `callbackDispatcher` (core/background, WorkManager)
- **Key logic:** WorkManager periodic 15' chạy trong **isolate riêng** (tự dựng DI, không Riverpod). **Guard dữ liệu cũ:** worker bỏ bước sinh cảnh báo nếu `data.age > alertMaxDataAgeMinutes=45'` (fetch fail → repo trả cache → tránh báo pha/giờ sai). Sinh **3 nhóm** thông báo: (1) thời điểm mưa (RainStatus), (2) tình hình thời tiết (WeatherCondition), (3) thay đổi nhiệt/ẩm (EnvChange). Chống spam: chỉ phát khi PHA mưa / NHÓM thời tiết đổi so với trạng thái lưu ở `AlertStateStore` (phase + category + **changeAt** + envNotified) — **ngoại lệ:** pha giữ nguyên nhưng `changeAt` lệch ≥ `rainTimeShiftRenotifyMinutes=15'` so với lần đã báo → phát bản **"Cập nhật: …"** (cùng ID → thay thế); notification ID cố định theo loại để thay thế thay vì chồng chất. Nội dung mưa kèm **giờ đồng hồ (HH:MM) format trực tiếp từ `rain.changeAt`** (không cộng phút vào now → hết drift theo tuổi cache; 0 phút → "ngay bây giờ") + **% khả năng mưa** (`rain.probabilityPct`); phân biệt "sắp tạnh" (rainStoppingSoon) vs "đã tạnh" (dry). `RainAlertBanner` trên màn hình hiển thị **cùng nội dung** (HH:MM + %) khớp notification. Mọi thông báo dùng `BigTextStyleInformation` (mở rộng đầy đủ, không cắt chữ).

### Bản tin thời tiết hằng ngày (daily digest)
- **Status:** ✅ done
- **Backend:** —
- **Mobile:** `DailyDigest` + `BuildDailyDigest` (usecase) · `BuildRainOutlook` (usecase mưa cả ngày) · `NotificationPrefsStore` + `DigestPrefs`/`DigestSlot` (SharedPreferences) · `scheduleDigests` (`digest_scheduler.dart`) · `digestAlarmCallback` (`core/background/digest_alarm.dart`) · `NotificationSettingsController` + provider `notificationSettingsProvider` · UI `_DailyDigestSettings` trong `SettingsScreen` · lập lịch qua **`android_alarm_manager_plus`** (ID `dailyDigestMorning=1005`, `dailyDigestEvening=1006`)
- **Key logic:** kênh thông báo **độc lập** với cảnh báo sự kiện — tóm tắt nhiệt độ + cảm giác như + hi/lo 24h + tình hình `WeatherCondition` + lời khuyên + **outlook mưa CẢ NGÀY theo buổi** (`BuildRainOutlook`: quét `hourly` còn lại của hôm nay, **4 buổi Đêm/Sáng/Chiều/Tối phủ 0–24h**, tách từng đợt mưa không liền kề, ví dụ "Chiều có mưa (~11:00–12:00, khả năng ~60% và ~15:00–17:00, khả năng ~70%). Sáng & tối khô ráo." / "Hôm nay ít khả năng mưa.") + gợi ý mưa tức thời từ `AnalyzeRain` (giờ HH:MM từ `changeAt` + %) + nhắc UV nếu `uvi≥digestUvWarnThreshold` + "Cập nhật lúc HH:MM" (theo `fetchedAt`). **Cơ chế = alarm chạy code nền** (`AndroidAlarmManager.periodic` lặp ngày, `exact + wakeup + allowWhileIdle + rescheduleOnReboot`): tại mốc giờ, `digestAlarmCallback` (isolate riêng, tự dựng DI) **FETCH dữ liệu tươi rồi mới hiển thị** — sửa lỗi cũ (`zonedSchedule` bake sẵn text → hiện dữ liệu cũ). `scheduleDigests(DigestPrefs)` chỉ lập/huỷ lịch (không truyền `WeatherData`), gọi lại ở 3 nơi: **main `_bootstrap`**, **`NotificationSettingsController`** (đổi enabled/giờ), **`background_worker._runWeatherCheck`**. Toạ độ nền lấy qua `resolveBackgroundCoords` (`core/background/background_location.dart`) — last-known (≤`backgroundLastKnownMaxAgeHours`=24h) hoặc fallback `LastLocationStore`. Hai mốc `morningMinutes`/`eveningMinutes` (mặc định 390/990 = 6h30/16h30) lưu phút-trong-ngày, chỉnh qua time picker; công tắc `enabled` (tắt → `cancel` cả 2). **AndroidManifest** khai báo `USE_EXACT_ALARM`/`SCHEDULE_EXACT_ALARM` (alarm) + receiver flutter_local_notifications (còn dùng cho `NotificationService.scheduleDaily` fallback).

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
| `currentPlaceProvider` | FutureProvider | location | `currentLocationProvider` + `locationRepositoryProvider` |
| `themeControllerProvider` | StateNotifierProvider | theme | SharedPreferences; UI Settings + `main.dart` |
| `notificationSettingsProvider` | StateNotifierProvider | alerts (digest) | `NotificationPrefsStore` (SharedPreferences); UI Settings |
| `routeControllerProvider` | StateNotifierProvider | fixed_route | `poiRepositoryProvider` (Drift + Overpass) |
| `notesControllerProvider` | StateNotifierProvider | notes | `noteLocalDataSourceProvider` (Drift) + `noteNotificationServiceProvider` |
| `poiRepositoryProvider` | Provider (DI) | fixed_route | `routeLocalDataSourceProvider` + `overpassDataSourceProvider` |
| `newsProvider` | FutureProvider | map_news | `currentLocationProvider` + `newsRepositoryProvider` (RSS) |
| `weatherProvider` | FutureProvider | weather | `currentLocationProvider` + `weatherRepositoryProvider` |
| `rainStatusProvider` | Provider | weather | `weatherProvider` |
| `weatherConditionProvider` | Provider | weather | `weatherProvider` |
| `*RepositoryProvider`, `*DataSourceProvider` | Provider (DI) | location/weather | hạ tầng ở `core/di/providers.dart` |

> Loại: `FutureProvider` (read) · `StateNotifierProvider` (mutation) · `StreamProvider` · `Provider`.
