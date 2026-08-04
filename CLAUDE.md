# KatoCast — CLAUDE.md

> **ĐỌC FILE NÀY ĐẦU TIÊN.** Đây là tài liệu gốc của project. File này tự động được nạp mỗi session.
> Trước khi làm bất kỳ task nào, hãy đọc đủ 3 tài liệu trong `.claude/docs/` để hiểu toàn bộ hệ thống:
> 1. [`.claude/docs/structure.md`](.claude/docs/structure.md) — cây thư mục & vai trò từng file
> 2. [`.claude/docs/features.md`](.claude/docs/features.md) — danh sách feature, trạng thái DB, providers
> 3. [`.claude/docs/callflows.md`](.claude/docs/callflows.md) — luồng hoạt động của hệ thống

---

## ⚠️ QUY TẮC BẮT BUỘC (đọc kỹ)

1. **Hiểu trước khi sửa.** Mọi session phải đọc `CLAUDE.md` + 3 file trong `.claude/docs/` trước khi chỉnh code.
2. **Sửa code xong → cập nhật docs.** Sau khi thêm/sửa/xóa code, **bắt buộc chạy `/sync-docs`** để đồng bộ
   `CLAUDE.md` và `.claude/docs/`. Stop-hook sẽ nhắc nếu bạn quên.
3. **Không sửa file generated.** Mobile: `*.g.dart`, `*.freezed.dart`. Backend: file trong `alembic/versions/` đã apply.
4. **Tài liệu là nguồn sự thật phụ.** Nếu code khác docs → sửa docs cho khớp code (không sửa code cho khớp docs).

---

## 1. Project là gì

**KatoCast** — hệ thống gồm:
- **Backend**: Python **FastAPI** (async), PostgreSQL, Redis (background jobs), Alembic migrations.
- **Mobile**: **Flutter** — Riverpod (state), Dio (network), Drift + SQLCipher (local DB mã hóa), GoRouter (navigation), Freezed (models).

> 📌 Phase 1 (mobile, client-only) đã hoàn thiện: định vị + thời tiết One Call 4.0 + thông báo thông minh. **Phase 2 đã khởi động:** app mở rộng thành **KatoAssistant** (trợ lý cá nhân) với feature **Theo dõi thông báo** (JLPT/MBA/…) chạy **kiến trúc hybrid** — **backend FastAPI** (`backend/`) crawl+diff+xác thực, mobile poll 1 lần/ngày. Cập nhật các bảng "Registry" bên dưới qua `/sync-docs` khi code đổi.

## 2. Kiến trúc tổng quan

```
┌──────────────┐     HTTPS/JSON      ┌──────────────────────────┐
│  Flutter App │ ◀──── Dio ────────▶ │  FastAPI (api/v1)        │
│              │                     │   → services → repos     │
│  Drift (local│                     │   → SQLAlchemy models    │
│  encrypted)  │                     │   → PostgreSQL           │
│  + sync queue│                     │   Redis (jobs/cache)     │
└──────────────┘                     └──────────────────────────┘
        │  offline-first: ghi local → đẩy lên qua sync queue khi online
```

### Backend layering (bắt buộc theo thứ tự)
`api/v1/*.py` → `services/*.py` → `repositories/*.py` → `models/*.py`
- **api**: chỉ routing + validation + `Depends(get_current_active_user)`.
- **service**: business logic, raise `HTTPException`, wrap mutation trong try/except + `await session.rollback()`.
- **repository**: chỉ data access (get/create/update/soft-delete). KHÔNG business logic.
- **schemas**: Pydantic v2 DTO (`XxxCreate`/`XxxRead`/`XxxUpdate`), dùng `model_dump()`/`model_validate()`.

### Mobile layering (feature-first)
`presentation/screens` → `providers (Riverpod)` → `data/repository` → (`api_service` | `Drift local`)
- Reads: `FutureProvider`. Mutations: `StateNotifierProvider` + `ref.invalidate()` sau khi xong.
- Error UI: dùng `extractUserMessage(e)` / `AppErrorWidget` — KHÔNG hiển thị `$e` trực tiếp.

## 3. Key Features Registry

> Phase 1 là **client-only** (Flutter gọi thẳng OpenWeatherMap One Call 3.0). Chưa có backend.

| Feature | Status | Backend | Mobile | Ghi chú |
|---------|--------|---------|--------|---------|
| Định vị (location) | ✅ | — | `features/location/*` (geolocator + geocoding + **Nominatim OSM**) | current + stream, distanceFilter 200m; **reverse geocoding 2 tầng**: ưu tiên **Nominatim** (`NominatimDataSource`, địa chỉ VN chi tiết **đường→phường→quận→thành phố**, `accept-language=vi`) → **fallback plugin `geocoding`** (offline) khi mạng lỗi/không đủ chi tiết. `Place` (+ `thoroughfare`) — AppBar hiện `shortLabel`, **header thân màn hình hiện `fullLabel` đầy đủ** (đường→phường→quận→`subAdministrativeArea`→tỉnh, bỏ trùng, không cắt) để dễ kiểm chứng app lấy đúng vị trí, tránh cắt kiểu "thành phố Hồ Chí Mi…" |
| Giao diện & cá nhân hóa (theme) | ✅ | — | `core/theme/*` + `features/settings/*` | Sáng/Tối/Hệ thống + bảng màu chọn sẵn (gồm **"Nâu Kato 🐾"** tông Bengal — dấu ấn con mèo Kato) + Material You (dynamic_color) + đổi màu theo thời tiết; lưu SharedPreferences; màn Settings (+ guide pin + mục "Về chú mèo Kato") |
| Thời tiết (weather) | ✅ | — | `features/weather/*` | One Call **4.0** (3 endpoint→chuẩn hoá); offline-first cache Drift; **stale-while-revalidate** (mở app hiện cache ngay, chỉ gọi API khi cache ≥15'); `AnalyzeRain` (neo mọi phép tính vào `now`, lọc điểm dự báo quá khứ, **kết hợp 3 nguồn**: quan trắc `current` đè nowcast khi TRỜI ĐÃ MƯA (`_obsIndicatesRain`) + nowcast khô vẫn đối chiếu hourly có tín hiệu mạnh (mm + pop≥0.6) để không mất cảnh báo sớm, trả `changeAt` timestamp tuyệt đối + **`rainEndsAt`/`durationMinutes`** (nối tiếp hourly khi mưa vượt cửa sổ nowcast) + **`segments`** = diễn biến từng đoạn cường độ (possible/nhỏ/vừa/to, `describeRainCourse` dựng câu "mưa vừa ~17:00–19:00, sau đó mưa nhỏ...") + `probabilityPct` theo pop của **giờ chứa sự kiện** (fallback giờ gần nhất), floor 80% **CHỈ khi ĐANG mưa** — pha "sắp mưa" hiện **pop THẬT** không ép sàn để không thổi phồng %), `DetectEnvChange`; `connectivityStatusProvider` cho badge offline (badge dùng `.toLocal()` + **clamp mốc tương lai** → "Vừa cập nhật"). **`WeatherData.fromCacheFallback`** đánh dấu cache cũ trả về do fetch lỗi (không phải fetch tươi). **Dữ liệu thiếu = null → UI "—"** (trường số `CurrentWeather` nullable, mapper `_toDoubleOrNull/_toIntOrNull`); thiếu `weather[]` → `conditionId=null` → "Không rõ tình hình" (không mặc định nắng). **UI mở rộng:** header địa điểm **đầy đủ** (`Place.fullLabel`), thẻ **CurrentWeatherCard** (UV kèm band màu + mây% + hi/lo + **chi tiết 4.0: điểm sương/áp suất/tầm nhìn/gió giật/hướng gió la bàn**), **HourlyList** (emoji tình hình + °C + **% (ưu tiên pop nowcast 15') + mm mưa** + ghi chú "pop là ước tính OWM"), thẻ **"Lưu ý hôm nay"** (`AdvisoryCard` ← `BuildAdvisories`: tình hình + UV + độ ẩm + gió + mưa) |
| Phân loại tình hình (condition) | ✅ | — | `weather/domain/entities/weather_condition.dart` + `ConditionCard` | nắng/mây/mưa nhỏ-to/dông/bão lớn/lốc + nhãn + lời khuyên + mức độ |
| Thông báo thông minh (alerts) | ✅ | — | `features/alerts/*` + `core/background` + `core/notifications` | Điều phối qua `applyBackgroundTriggers`: **cả 3 lớp cùng bật** (FG service khi được bật + alarm exact + WorkManager) vì **`CycleLock` bảo đảm chỉ MỘT chu kỳ thực sự chạy** → nhiều lớp = nhiều đường hồi phục độc lập; alarm arm **lệch nửa chu kỳ** so với FG. **⚠️ 3 bug nền đã fix** (nguyên nhân "tối vẫn chạy, sáng ra không lấy dữ liệu/không báo, restart máy thì lại chạy" + "một tin báo mấy lần"): **(1)** FG và alarm bị **dính pha** (arm liền nhau, và alarm gọi `restartService()` reset pha FG) → hai isolate cùng mở `katocast.sqlite` (Drift không hỗ trợ) → `database is locked`, mà `purgeOlderThan` lại nằm NGOÀI try nên lỗi đó **làm sập cả `runWeatherCheck`** và bị `catch(_)` nuốt sạch → fix bằng `CycleLock` (lock **bằng file**, stale 3'), **một `AppDatabase` mỗi chu kỳ**, purge chỉ **1 lần/ngày** trong try, alarm không `restartService()` nữa, `ApiClient.close()` mỗi chu kỳ; **(2)** đêm 21h→5h treo trên **một alarm duy nhất** → nay nhảy **từng chặng 2h** (`kNightHopInterval`, không lấy dữ liệu, chỉ tự sửa chuỗi) + **WorkManager LUÔN bật** (lịch do JobScheduler của HĐH giữ nên sống sót khi chuỗi one-shot đứt; dựng lại alarm chỉ khi `weatherAlarmChainStatus().overdue`) + FG ngoài khung vẫn `updateService` "đang nghỉ" thay vì đóng băng text tối qua; **(3)** thông báo lặp do `AlertStateStore` đọc-`show`-rồi-mới-ghi **không có lock** + `SharedPreferences` cache **riêng theo isolate** (isolate FG sống hàng giờ không thấy gì isolate alarm ghi) → fix bằng **`prefs.reload()` trong `read()`** + chuỗi đọc-tính-ghi trong `CycleLock`. **⚠️ VÒNG 2 — 5 lỗi tìm từ NHẬT KÝ THẬT (28–29/07/2026), 2 trong số đó do bản sửa vòng 1 gây ra:** **(4)** `CycleLock.runGuarded` **BỎ RƠI bản tin/poll tin** (`Bản tin · bỏ lượt: chu kỳ đang chạy · chủ: work` → callback hẹn lại NGÀY MAI = mất hẳn bản tin của ngày đó) → thêm **`CycleLock.runWaiting`**: chờ 75s rồi **chạy bất chấp**, và KHÔNG nhả lock của lớp khác; lock chỉ để giảm tranh chấp DB, không được hy sinh thông báo mỗi-ngày-một-lần. **(5)** chuỗi alarm **đứt 7h18** vì re-arm nằm CUỐI callback (`06:34:03 alarm nổ` → im lặng, không kịp re-arm) → **RE-ARM NGAY ĐẦU callback** ở cả 3 đường alarm, chuỗi tự duy trì dù isolate bị giết giữa đường. **(6)** `_reviveForegroundServiceIfNeeded` là **nghi phạm giết isolate** (Android 12+ chặn start FGS từ nền) → đặt SAU re-arm + log mọi nhánh *(→ VÒNG 3 xác nhận nó là hung thủ và XOÁ hẳn)*. **(7)** **vị trí nền bị CŨ khi di chuyển**: `getLastKnownPosition()` luôn null trên máy thật nên nền mãi dùng `LastLocationStore` chỉ cập nhật lúc mở app, mà app **chưa bao giờ xin quyền "Luôn cho phép"** → thêm `savedAt` cho store, **chủ động xin fix mới** khi toạ độ cũ hơn 25', log **tên địa điểm + khoảng đã dịch chuyển**, và `requestBackgroundLocation()` hiện trong trang Nhật ký + Settings. **(8)** **nhận định mưa sai**: `> 0.1 mm/h` tại MỘT mốc đủ tuyên bố "đang mưa" → trời âm u thành "Mưa nhỏ 100%", pha **kẹt `raining` >15h** nên `rainStartingSoon` không bao giờ tới và app im lặng hoàn toàn → tách **`rainNowThresholdMmH=0.5` × 2 mốc liên tiếp** để tuyên bố đang mưa (giữ 0.1 cho dự báo phía trước), `_obsIndicatesRain` không tin `conditionId` suông với mã YẾU (500/3xx cần `rain1h>0`), log thêm **số liệu thô**. **(9)** `AlertStateStore` so với trạng thái từ **20:57 hôm trước** → thêm `updatedAt` + **hết hạn sau 2h** = khởi đầu mới. **⚠️⚠️ VÒNG 3 — NHẬT KÝ THẬT 01–04/08/2026, tìm ra NGUYÊN NHÂN GỐC của "dùng càng lâu / càng không restart máy thì càng lỗi" (app đứng im 46 TIẾNG: 02/08 14:28 → 04/08 12:33, `chiếm lại lock quá hạn · đã 2765m`; hôm trước 17h55):** **(10) 🔴 APP TỰ SẬP THÀNH VÒNG LẶP RỒI BỊ HĐH FORCE-STOP.** `flutter_foreground_task` gọi `startForeground()` trong `onStartCommand` **KHÔNG có try/catch**; Android 12+ chặn start FGS từ nền nên `ForegroundServiceStartNotAllowedException` bay lên luồng chính Java → **CHẾT TIẾN TRÌNH** (Dart `catch` KHÔNG bắt được vì lỗi ở tầng Service). Nhật ký 02/08 in đúng dấu vết: 12:58, 13:13, 13:28, 13:43, 14:13, 14:28 — mỗi mốc ghi "thử hồi sinh" rồi **im lặng tuyệt đối** (không có cả dòng thành công lẫn dòng lỗi). Sau ~6 lần sập, HĐH force-stop app → **hủy SẠCH alarm one-shot + job WorkManager** → im 46 tiếng tới khi mở app. → **XOÁ hẳn việc start FGS từ isolate nền** (`_reportForegroundServiceState` chỉ GHI NHẬN qua **`ForegroundServiceHealth`**); đường bật lại HỢP PHÁP: **`onResume` của app** (`main.dart`), `RestartReceiver` của plugin (dùng `setAlarmClock` — được HĐH miễn trừ), và **nút "Bật lại theo dõi liên tục"** trong trang Nhật ký; im lặng >2h trong khung giờ → **MỘT thông báo nhắc mở app** (channel `service_health`, cooldown 6h). **(11) 🔴 VÌ SAO FG SERVICE CHẾT NGAY TỪ ĐẦU: Android 15+ cắt FGS kiểu `dataSync` sau 6 GIỜ tích lũy/24h** (app build `targetSdk 36`), gọi `Service.onTimeout()` — mà plugin 8.17 **không cài `onTimeout`** → HĐH dừng service; đồng hồ chỉ reset khi app lên foreground = đúng triệu chứng "mở app/restart máy thì chạy, để lâu thì chết". → đổi `foregroundServiceType` **`dataSync` → `location`** (không bị giới hạn thời lượng, và ĐÚNG bản chất: mỗi chu kỳ service đều phân giải vị trí) + quyền `FOREGROUND_SERVICE_LOCATION`; `startWeatherForegroundService` **kiểm tra quyền vị trí TRƯỚC khi start** (thiếu quyền → `startForeground` ném SecurityException = sập app) và **đọc `ServiceRequestFailure`** thay vì bỏ trắng giá trị trả về. **(12)** `CycleLock.release()` xoá file lock **vô điều kiện** → chu kỳ treo bị chiếm lại, tỉnh lại rồi **xoá lock của chủ MỚI** → chu kỳ thứ ba chen vào giữa lúc chủ mới đang mở DB → thêm **token mỗi lượt chiếm**, chỉ chủ thật mới xoá được. **(13)** WorkManager có ràng buộc `NetworkType.connected` → **mất mạng là watchdog dựng-lại-chuỗi-alarm KHÔNG chạy**, đúng lúc cần nhất → bỏ ràng buộc; thêm **FG tick cũng dựng lại chuỗi alarm khi `overdue`** (lưới thứ hai) và WorkManager cũng báo cáo tình trạng FG. **(14)** "đang mưa" SAI vì `rain1h` là số **TÍCH LŨY 1 giờ** nên còn dư ~1h sau khi mưa tạnh (kèm mã OWM 500 giữ nguyên): nhật ký 01/08 12:32–12:55 `nowcast 0.00 mm/h · rain1h 0.74 mm · mã 500` → app báo "Trời đang mưa · còn mưa **80%**" (sàn xác suất chỉ áp khi ĐANG mưa) và pha **kẹt `raining`** → im lặng hàng chục phút → `_obsIndicatesRain` nhận thêm `nowcastSawNoRainAtAll`: nowcast phủ định SẠCH cửa sổ thì **nowcast thắng**, van HẸP nên KHÔNG chặn mã MẠNH (2xx/501+), `rain1h ≥ 2mm` (`rainObsHeavyMm1hThreshold`), hay khi nowcast thấy mưa SẮP tới. **(15)** mỗi lần app hồi sinh sau khoảng đứt, `AlertStateStore` hết hạn → `previousCategory == null` → **luôn phát một thông báo vô ích** ("🌤️ Nhiều mây", "☁️ Trời u ám" — 02/08 06:50, 04/08 12:33, chiếm phần lớn "4 thông báo/24h") → lần KHỞI ĐẦU chỉ báo khi `WeatherSeverity ≥ notice` (mưa/dông/sương mù), trời quang/mây thì im. **(16)** `LogHealth` chỉ nhận dòng `arm` có `source == alarm` nên bỏ qua mốc mới do lớp `ui`/`worker` đặt → thẻ hiện "Alarm kế tiếp 14:43 — **ĐÃ QUÁ HẠN 45h50**" ngay sau khi vừa đặt mốc mới → lọc theo nhãn ổn định `loại: thời tiết` (`LogTags.armKindWeather`). **(17)** `AppLog._approxSize` là static **riêng mỗi isolate** → isolate mang số cũ rotate oan file mới còn bé và **xoá `kato.1.log`** = mất lịch sử đúng lúc cần tra → **xác minh `file.length()` thật trước khi rotate**. Foreground service (live nhiệt độ + giờ, Doze, `allowWifiLock=false`, re-assert ghim ghi chú; text **thêm `· ⚠️ dữ liệu cũ`** khi fetch nền thất bại/quá 45'); alarm exact **thử lại sớm 5' khi fetch fail** (`scheduleWeatherAlarm(retrySoon)`). **Chu kỳ tùy chỉnh 5/10/15/30'**. **Khung giờ hoạt động:** mặc định **5h–21h** (hoặc 24/7) — cả 3 lớp gate `isWithinActiveHours(now)`; digest KHÔNG bị chặn. Guard quota bám chu kỳ (cache tươi hơn chu kỳ−1' → không gọi API). **Mở app chạy `runWeatherCheck` ngay** (qua lock). **Mọi `catch (_)` trên đường nền → `catch (e, st)` + `AppLog.e`** (xem feature Nhật ký hoạt động). 3 nhóm (mưa/tình hình/môi trường), chống spam; nội dung mưa kèm **giờ + % + giờ tạnh/thời lượng + diễn biến từng đoạn cường độ** + **giọng mèo Kato** (`KatoVoice` prepend câu mở đầu); báo lại "Cập nhật" khi mưa đến SỚM ≥15' / DỜI MUỘN ≥45' (bất đối xứng chống spam trôi giờ); **nhắc lại "Sắp mưa: còn ~N phút" khi onset áp sát ≤35'** sau lần báo từ xa (`AlertStateStore` lưu thêm `notifiedAt`; mốc đã báo chỉ ghi đè khi thật sự phát — chống drift); bỏ cảnh báo nếu dữ liệu >45'. ⚠️ **Vuốt tắt app trên OEM diệt tiến trình (Nubia/MyOS, Xiaomi/HyperOS…) = force-stop → hủy mọi alarm + FG service**; chắc chắn nhất là **KHÓA app trong recents 🔒** (hoặc đừng vuốt tắt), thêm **Tự khởi động + Không giới hạn pin** (onboarding dẫn tới, `MainActivity` MethodChannel `katocast/oem` deep-link Autostart đa-hãng). FG service khai báo `android:stopWithTask="false"` (cứu ca task-removal, không cứu force-stop; đồng thời bật đường tự start lại của plugin qua `RestartReceiver` + `setAlarmClock`). **KHÔNG lớp nền nào được start FGS** — xem (10) |
| Bản tin thời tiết hằng ngày (digest) | ✅ | — | `features/alerts/*` (BuildDailyDigest, NotificationPrefsStore, notificationSettingsProvider, **digest_scheduler**) + `core/background/digest_alarm` + `weather/.../build_rain_outlook` + `weather/.../digest_settings_card` | Tự gửi tóm tắt vào **danh sách nhiều mốc giờ TÙY Ý** (thêm/xóa trong **màn Thời tiết** — `DigestSettingsCard`; mặc định 6h30 & 16h30, migrate từ mô hình 2 mốc cũ) qua **`android_alarm_manager_plus`** dùng **`oneShotAt` exact+allowWhileIdle** (KHÔNG `periodic`; mỗi mốc 1 alarm ID **dải động `digestBase + index`**; callback **re-arm theo index**). **Fix không nổ:** kiểm tra `canScheduleExactAlarms` → thiếu quyền thì **fallback `exact:false`** + dòng cảnh báo xin quyền; xin quyền exact-alarm lúc khởi động; `scheduleDigests(prefs,{force})` idempotent, **throttle self-heal 1h + chỉ hủy slot thừa + anti-clobber `_justPassed` 20'** (fix bản tin 6h30 bị tick FG hủy-dời sang mai & fix ANR do burst 64 binder call mỗi tick; app mở/đổi cài đặt gọi `force:true`). **Nút tự chẩn đoán** "Đặt bản tin thử sau 1 phút" (`scheduleDigestTest` → `NotificationIds.digestTest=1099`, callback hiện thông báo xác nhận, không re-arm) để phân biệt lỗi lập lịch vs force-stop OEM. Tại mốc giờ `digestAlarmCallback` **fetch dữ liệu tươi rồi hiển thị**. Nội dung: **câu chào Kato** (sáng/chiều) + **outlook mưa cả ngày theo buổi** + gợi ý mưa tức thời (giờ + **giờ tạnh**) + hi/lo + **UV theo mức**. ⚠️ **AndroidManifest PHẢI khai báo** `AlarmService` + `AlarmBroadcastReceiver` + `RebootBroadcastReceiver` của `android_alarm_manager_plus` (plugin 4.0.x manifest rỗng); thiếu → mọi alarm crash "Component ... does not exist" → không nổ. Đừng xóa. |
| Module 1 — Map & News | ✅ | — | `features/map_news/*` | bản đồ OSM (flutter_map) + lớp mưa OWM; tin tức RSS thời tiết (`MapScreen`, `/map`) |
| Module 2 — Fixed Route POI | ✅ | — | `features/fixed_route/*` | lưu lộ trình (Drift) + quét POI dọc đường qua Overpass/OSM (`RouteScreen`, `/routes`) |
| Ghi chú (notes) | ✅ | — | `features/notes/*` + `core/notifications/notification_response_handler.dart` | Note text/checklist, màu, tìm kiếm, khu "Đã xong"; **ghim sticky** lên thanh thông báo (`ongoing`, sống qua "Xoá tất cả", chỉ gỡ bằng nút **"Đã đọc"** — note giữ nguyên trong app); **hẹn nhắc** một lần/hằng ngày/hằng tuần theo thứ (`zonedSchedule` exact, sống qua reboot); re-assert ghim ở bootstrap + worker 15'; ID scheme `10000 + noteId*16 + slot` (`NotesScreen` `/notes`) |
| Nhật ký hoạt động (diagnostics) | ✅ | — | `core/diagnostics/*` + `features/diagnostics/*` | **Trang `/diagnostics`** ("Nhật ký hoạt động", vào từ Settings) để soi app đã làm gì: **lúc nào, lớp nào chạy** (fg/alarm/worker/digest/announce/ui), **vị trí lấy từ đâu + tuổi + ĐỊA CHỈ THỰC TẾ** (khoá `địa chỉ`: số nhà → đường → phường/xã → quận/huyện → tỉnh/thành, do **`PlaceLabelResolver`** dựng qua Nominatim; trước đây chỉ có nhãn thô tới tỉnh/thành nên nhìn toạ độ `10.8524,106.6507` không kiểm chứng được app lấy đúng chỗ hay không), **dùng cache hay gọi API kèm lý do**, kết quả API + thời lượng/lỗi, pha mưa + mốc + xác suất, **đã báo gì (id + nội dung) hay bỏ qua vì lý do gì**, mốc alarm kế tiếp, lượt bị bỏ do chống chạy chồng. Lưu **file JSONL** `<appDocs>/logs/kato.log` — **CỐ TÌNH không dùng Drift** để log được cả khi DB bị khoá (chính là lỗi cần truy); rotate 512KB × 2 file, giữ **7 ngày / 5000 dòng**. `AppLog` static dùng ở mọi isolate, **không bao giờ ném lỗi ra ngoài**; `LogEntry.tryParse` bỏ dòng ghi dở thay vì sập trang. **Mọi `catch (_)` trên đường nền đã đổi thành `catch (e, st)` + `AppLog.e`** — trước đây một chu kỳ thất bại không để lại dấu vết nào. `LogHealth` suy tình trạng từ chính nhật ký (không có store thứ hai): chu kỳ/fetch/thông báo gần nhất, alarm kế tiếp, thống kê 24h và **`longestGap24h`** phát hiện "app ngủ mất mấy tiếng"; mốc alarm kế tiếp lọc theo nhãn `loại: thời tiết` (không theo `source` — xem bug (16) ở feature alerts). UI: thẻ Tình trạng + thẻ Cấu hình & quyền (**"Theo dõi liên tục: BỊ HỆ THỐNG DỪNG — N giờ trước"** + nút **"Bật lại theo dõi liên tục"**, chỗ HỢP PHÁP duy nhất để start FGS) + filter chip + tìm kiếm + Copy/Xoá |
| Theo dõi thông báo (announcements) | ✅ | **`backend/`** (FastAPI) | `features/announcements/*` + `core/background/announcement_alarm.dart` | **Kiến trúc HYBRID** (mở rộng app → **KatoAssistant**). **Backend** crawl **whitelist nguồn GỐC chính thức** (JLPT: jlpt.jp/jees; MBA: nguồn trường tự cấu hình) → **diff phát hiện mục MỚI** (dedup `content_hash`) → **xác thực** (Claude Haiku phân loại khớp chủ đề + tóm tắt, có rule-based fallback keyword+ngày) → lưu Postgres/SQLite → expose `GET /api/v1/announcements`. **Mobile** poll backend **1 lần/ngày** qua **alarm exact `oneShotAt` tự re-arm** (copy mẫu digest; `announcementCheckCallback`, `scheduleAnnouncementCheck`), lọc mục chưa thấy bằng Drift `seen_announcements`, hiện thông báo **giọng Kato** (`KatoVoice.announcement`) kèm **domain nguồn để kiểm chứng** (chống fake), tap → `/announcements`. **Chống báo lại cùng một tin (đã fix):** `markSeen` chạy **TRƯỚC** `show` (trước đây show trước — nếu lượt ghi Drift thất bại vì DB bị isolate khác khoá thì tin đã hiện mà không được ghi nhận → lượt poll sau BÁO LẠI), kèm `unmarkSeen` bù trừ khi show lỗi; `scheduleAnnouncementCheck` nay có **throttle + guard `justPassed`** dùng chung với digest qua **`AlarmScheduleGuard`** (trước đây `cancel` + arm lại ở MỌI chu kỳ nền nên đua với re-arm từ isolate alarm); cả lượt poll chạy trong **`CycleLock`**; ID thông báo cấp theo **bộ đếm xoay vòng** thay cho `remoteId % 500` (hai tin lệch đúng 500 từng đè mất nhau). Màn **AnnouncementsScreen** (list + bật/tắt + giờ kiểm tra + chọn chủ đề JLPT/MBA + nút **"Kiểm tra tin mới ngay"** `checkAnnouncementsNow`, mở URL nguồn qua url_launcher). Chủ đề generic → thêm bất kỳ (học bổng/visa…) chỉ cần thêm `watch_source`. Dùng chung plugin `android_alarm_manager_plus` với digest nên KHÔNG cần khai báo manifest thêm. **Lịch & mốc hạn:** backend `exam_events` (mốc đăng ký/thi/kết quả, `curated` = lịch chuẩn seed từ nguồn chính thức, `GET /api/v1/events`) — **độ chính xác 3 tầng**: (1) lịch chuẩn seed (JLPT kỳ 7&12/2026, ngày xác thực từ info.jees-jlpt.jp), (2) regex `date_extract` trích ngày trong tin (JP `年月日`/令和 + VN dd/mm + ISO, gán nhãn theo keyword gần nhất) → hiển thị "chưa kiểm chứng", (3) **người dùng sửa/thêm/ghi đè** (Drift `event_overrides`, LUÔN ưu tiên, badge "đã kiểm chứng"). Trạng thái còn hạn/hết hạn **tính client-side** (`computeStatus` → chip màu đỏ/cam/xanh/xám) để luôn tươi. Section "📅 Lịch & hạn" + `EventEditDialog` (4 date picker) trong AnnouncementsScreen. **KHÔNG dùng LLM** cho trích ngày |

> Status: 📋 planned · 🚧 in progress · ✅ done

## 4. API Endpoints Summary

> **Backend KatoAssistant** (`backend/`, FastAPI async — theo dõi thông báo). App vừa tiêu thụ API ngoài, vừa gọi backend này qua `AppConfig.backendBaseUrl`.

| Group | Method | Path | Mô tả |
|-------|--------|------|-------|
| KatoAssistant BE | GET | `/api/v1/announcements?topic=&since=` | danh sách thông báo (JLPT/MBA/…) đã diff & xác thực; `since` lọc mục mới; mỗi mục kèm `extracted_dates` (ngày regex tự phát hiện, CHƯA kiểm chứng) |
| KatoAssistant BE | GET | `/api/v1/events?topic=` | lịch CÓ CẤU TRÚC (exam_events): mốc đăng ký/thi/kết quả; `curated=true` = lịch chuẩn đã seed/kiểm chứng |
| KatoAssistant BE | GET/POST | `/api/v1/watch-sources` | liệt kê / thêm nguồn GỐC theo dõi (topic, url, item_selector, keywords) |
| KatoAssistant BE | POST | `/api/v1/crawl?topic=` | chạy crawl ngay (cron/HTTP gọi); trả số mục mới |
| KatoAssistant BE | GET | `/health` | health check + cờ có LLM |

> App cũng tiêu thụ API ngoài (client-only cho các feature khác):

| Group | Method | Path | Mô tả |
|-------|--------|------|-------|
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/current` | thời tiết hiện tại (`data[0]`) |
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/timeline/15min` | nowcast 15' → chuẩn hoá thành `minutely` |
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/timeline/1h` | dự báo giờ → `hourly` |
| Nominatim (OSM) | GET | `nominatim.openstreetmap.org/reverse` | reverse geocoding toạ độ → địa chỉ VN chi tiết (đường/phường/quận); `format=jsonv2`, `accept-language=vi`, User-Agent OSM, ≤1 req/s |
| OpenStreetMap | GET | `tile.openstreetmap.org/{z}/{x}/{y}.png` | tile bản đồ nền (flutter_map) |
| OpenWeatherMap tiles | GET | `tile.openweathermap.org/map/precipitation_new/...` | lớp phủ lượng mưa trên bản đồ |
| Overpass (OSM) | POST | `overpass-api.de/api/interpreter` (+ mirror trong `AppConfig.overpassEndpoints`) | quét POI (amenity/shop) quanh lộ trình; thử lần lượt nhiều mirror để chịu lỗi |
| RSS | GET | `vnexpress.net/rss/thoi-tiet.rss` | tin tức thời tiết (parse XML) |

## 5. Database Models

> DB cục bộ trên thiết bị (Drift) — xem `mobile/lib/core/database/app_database.dart`.

| Table | Mô tả | Quan hệ chính |
|-------|-------|---------------|
| `weather_cache` | Cache JSON One Call theo `locationKey` (lat,lng làm tròn) + `fetchedAt` | PK = locationKey |
| `fixed_route_points` | Điểm lộ trình cố định (routeId, lat, lng, seq, label) | gom theo `routeId` |
| `notes` | Ghi chú (title, body, colorIndex, pinned, done, remindAt, repeat, weekdaysMask, createdAt/updatedAt) | 1—n `note_items` |
| `note_items` | Mục checklist (noteId, content, done, seq) | thuộc `notes` qua noteId |
| `seen_announcements` | Thông báo (JLPT/MBA…) ĐÃ hiển thị — chống báo lại (contentHash **unique**, remoteId, seenAt) | PK = id; khoá tự nhiên `contentHash` |
| `event_overrides` | Bản SỬA/THÊM của người dùng cho lịch (ExamEvent) — luôn ưu tiên hơn backend (sourceEventId **unique** nullable, sessionLabel, regStart/regEnd/examDate/resultDate, note, updatedAt) | PK = id; `sourceEventId` link event backend (null = tự thêm) |

> schemaVersion = **4** (v1→v2 notes/note_items; v2→v3 seen_announcements; v3→v4 event_overrides — qua `MigrationStrategy.onUpgrade`).
>
> **Backend DB** (Postgres/SQLite, SQLAlchemy — `backend/app/models/`): `announcements` (topic, title, summary, source_url, source_domain, content_hash unique, verified, score, first_seen_at, **extracted_dates** JSON regex) · `watch_sources` (topic, url, parser_type, item_selector, keywords, enabled) · **`exam_events`** (topic, session_label, registration_start/end, exam_date, result_date, source_url/domain, curated, note, updated_at — lịch chuẩn seed). Migration qua Alembic (`backend/alembic/` — 0001 initial, 0002 events+extracted_dates).

## 6. Shared Utilities

- Backend: `backend/app/core/config.py` (Pydantic settings), `backend/app/db/` (async engine/session/base). Layering `api/v1` → `services` (`crawl_service` LÕI: fetch→parse→diff `content_hash`→verify; `verify_service`: Claude Haiku + rule-based fallback) → `repositories` → `models`. Cron: `python -m app.jobs.daily_crawl`; seed nguồn: `app.jobs.seed_sources`. Xem `backend/README.md`.
- Mobile shared: `mobile/lib/shared/utils/error_handler.dart` → `extractUserMessage`; widgets `AppErrorWidget`, `LoadingWidget`, `PermissionDeniedWidget`.
- Mobile core: `core/kato/kato_voice.dart` (**KatoVoice** — giọng điệu mèo Kato tập trung cho thông báo/UI), `core/config/app_config.dart` (API key + ngưỡng + endpoint dịch vụ ngoài: Overpass mirror, OSM/OWM tile, RSS + `User-Agent` + hằng số nhật ký), **`core/diagnostics/`** (`AppLog` ghi nhật ký JSONL dùng được ở MỌI isolate + `LogEntry`/`LogSource`/`LogTags`/`LogHealth`), `core/di/providers.dart` (DI Riverpod hạ tầng), `core/network/` (Dio + connectivity; `ApiClient.close()` — BẮT BUỘC gọi ở isolate nền), `core/error/` (failures/exceptions), `core/permissions/`, `core/notifications/`, `core/background/` (foreground service + alarm exact + WorkManager, đều gọi `runWeatherCheck` **qua `CycleLock`**; `AlarmScheduleGuard` dùng chung cho digest & poll tin; **`ForegroundServiceHealth`** theo dõi FG service sống/chết xuyên isolate), `core/database/` (Drift).
- Mobile location: **`PlaceLabelResolver`** (`features/location/data/place_label_resolver.dart`) — toạ độ → **địa chỉ đầy đủ** dùng được ở MỌI isolate: Nominatim + cache theo **KHOẢNG CÁCH** (150m, chịu được nhiễu GPS 0–51m quan sát thực tế) + hàng rào giãn cách 1'/lần (chính sách OSM) + fallback plugin `geocoding`; đường UI `getPlace()` **seed sẵn cache** để nền dùng lại khỏi tốn request.

## 7. Quy trình làm việc & công cụ

| Khi cần | Dùng |
|---------|------|
| Thêm feature mới (BE/mobile) | `/add-feature` |
| Debug backend FastAPI | `/debug-backend` |
| Debug Flutter mobile | `/debug-mobile` |
| **Cập nhật docs sau khi sửa code** | **`/sync-docs`** |

### File quan trọng nhất (cập nhật khi project lớn lên)
- `backend/app/main.py`, `backend/app/api/router.py`, `backend/app/core/config.py`
- `backend/app/services/crawl_service.py` (**LÕI** crawl+diff+verify+set extracted_dates), `backend/app/services/verify_service.py` (Claude Haiku + rule-based fallback)
- `backend/app/services/date_extract.py` (**regex trích ngày** JP/VN/ISO + gán nhãn — KHÔNG LLM)
- `backend/app/models/exam_event.py` + `backend/app/api/v1/events.py` + `backend/app/repositories/exam_event_repo.py` (lịch có cấu trúc)
- `backend/app/jobs/daily_crawl.py` (cron entrypoint), `backend/app/jobs/seed_sources.py` (whitelist nguồn), `backend/app/jobs/seed_events.py` (**seed lịch chuẩn JLPT** — ngày xác thực từ nguồn chính thức)
- `mobile/lib/core/background/announcement_alarm.dart` (**callback poll tin** tự re-arm + `checkAnnouncementsNow`)
- `mobile/lib/features/announcements/data/announcement_scheduler.dart` (alarm 1 lần/ngày, copy mẫu digest)
- `mobile/lib/features/announcements/data/announcement_repository.dart` (nối backend + dedup Drift `seen_announcements`)
- `mobile/lib/features/announcements/domain/entities/exam_event.dart` + `event_status.dart` (**computeStatus** còn hạn/hết hạn client-side)
- `mobile/lib/features/announcements/data/event_repository.dart` (**merge** lịch backend + `event_overrides`, bản sửa tay ưu tiên) + `event_remote_data_source.dart`
- `mobile/lib/features/announcements/presentation/widgets/event_edit_dialog.dart` (Sửa/Thêm mốc — 4 date picker)
- `mobile/lib/features/announcements/presentation/screens/announcements_screen.dart` (UI list + cài đặt + nút test + section "📅 Lịch & hạn")
- `mobile/lib/main.dart`, `mobile/lib/core/app_router.dart`, `mobile/lib/core/network/api_client.dart`
- `mobile/lib/core/config/app_config.dart` (API key + ngưỡng tinh chỉnh)
- `mobile/lib/core/diagnostics/app_log.dart` (**AppLog** — nhật ký JSONL bền, dùng ở mọi isolate, KHÔNG bao giờ ném lỗi; rotation **xác minh `file.length()` thật trước khi rotate** vì `_approxSize` là static riêng mỗi isolate + prune) + `log_entry.dart` / `log_tags.dart` (`armKindKey`/`armKindWeather` — nhãn phân biệt loại alarm) / `log_health.dart` (**LogHealth** suy tình trạng + `longestGap24h`; mốc alarm kế tiếp lọc theo NHÃN, không theo `source`)
- `mobile/lib/features/diagnostics/presentation/screens/diagnostics_screen.dart` (**trang `/diagnostics`** — Tình trạng + Cấu hình & quyền + filter + tìm kiếm + Copy/Xoá) + `providers/diagnostics_providers.dart`
- `mobile/lib/core/background/cycle_lock.dart` (**`CycleLock`** — lock BẰNG FILE chống chạy chồng giữa các isolate; `runGuarded` cho chu kỳ lặp lại, **`runWaiting` cho bản tin/poll tin** — chờ rồi chạy bất chấp, không được bỏ rơi thông báo mỗi-ngày-một-lần; **token mỗi lượt chiếm** để chu kỳ bị chiếm lại không xoá lock của chủ mới)
- `mobile/lib/core/background/service_health.dart` (**`ForegroundServiceHealth`** — GHI NHẬN FG service sống/chết, **TUYỆT ĐỐI KHÔNG start FGS từ nền**; nhắc mở app khi im lặng >2h; đọc `deadFor()` cho trang Nhật ký)
- `mobile/lib/features/location/data/place_label_resolver.dart` (**`PlaceLabelResolver`** — toạ độ → địa chỉ đầy đủ cho nhật ký, cache theo khoảng cách + giãn cách OSM)
- `mobile/lib/features/location/data/last_location_store.dart` (toạ độ nền + **`savedAt`** — không có mốc thì không biết đang báo thời tiết cho chỗ cũ bao lâu)
- `mobile/lib/core/permissions/permission_service.dart` (**`requestBackgroundLocation`** — quyền "Luôn cho phép", điều kiện BẮT BUỘC để nền tự cập nhật vị trí khi di chuyển)
- `mobile/lib/core/background/alarm_schedule_guard.dart` (**`AlarmScheduleGuard`** — throttle self-heal + `justPassed` + `nextInstanceOf` dùng CHUNG cho digest & poll tin)
- `mobile/lib/core/background/background_triggers.dart` (**`applyBackgroundTriggers`** — cả 3 lớp cùng bật, alarm arm **lệch nửa chu kỳ** so với FG)
- `mobile/lib/core/background/weather_check.dart` (**LÕI** `runWeatherCheck({source, db})` + guard quota + purge cache 1 lần/ngày + log mọi quyết định)
- `mobile/lib/core/background/foreground_service.dart` (foreground service `flutter_foreground_task` — **kiểu `location`, KHÔNG `dataSync`** (Android 15+ cắt dataSync sau 6h/24h), chu kỳ từ prefs, `allowWifiLock=false`, toàn bộ phần dùng DB trong `CycleLock`, ngoài khung giờ vẫn cập nhật thông báo "đang nghỉ", tick cũng dựng lại chuỗi alarm khi `overdue`; `startWeatherForegroundService({allowRestart})` **chỉ được gọi khi app đang HIỂN THỊ** — kiểm tra quyền vị trí trước, đọc `ServiceRequestFailure`, trả `bool`)
- `mobile/lib/core/background/weather_alarm.dart` (alarm exact BACKSTOP luôn tự re-arm; **`kNightHopInterval=2h`** chặng đêm thay cho một alarm treo cả đêm; `weatherAlarmChainStatus()` cho watchdog WorkManager+FG; **CHỈ ghi nhận** tình trạng FG service qua `ForegroundServiceHealth` — KHÔNG start FGS từ nền (bản cũ làm vậy và sập cả tiến trình))
- `mobile/android/app/src/main/kotlin/.../MainActivity.kt` (MethodChannel `katocast/oem`: deep-link trang Tự khởi động/Autostart đa-hãng + battery settings)
- `mobile/lib/core/background/background_worker.dart` (WorkManager **LUÔN bật** — lịch do JobScheduler của HĐH giữ nên sống sót khi chuỗi one-shot đứt; clamp ≥15', **KHÔNG ràng buộc mạng** để watchdog vẫn chạy khi mất mạng, dựng lại alarm khi `overdue` + báo cáo tình trạng FG service)
- `mobile/lib/core/background/background_prefs.dart` (bật/tắt foreground service + chu kỳ nền 5/10/15/30' + **khung giờ hoạt động**: `isWithinActiveHours`/`nextActiveWindowStart` — gate 3 lớp trigger, hỗ trợ khung qua nửa đêm)
- `mobile/lib/features/weather/domain/usecases/analyze_rain.dart` (logic mưa cốt lõi — **`_nowcastSaysRainingNow`: ngưỡng RIÊNG + yêu cầu DUY TRÌ để tuyên bố "đang mưa"**, **`_obsIndicatesRain(nowcastSawNoRainAtAll:)`** không tin mã OWM yếu suông VÀ không để `rain1h` tích lũy đè nowcast đã phủ định sạch cửa sổ (van hẹp: mã mạnh / `rain1h ≥ 2mm` / nowcast thấy mưa sắp tới thì quan trắc vẫn thắng), quan trắc đè nowcast + `changeAt` + `rainEndsAt` + `segments`)
- `mobile/lib/features/weather/domain/entities/uv_advice.dart` (UV → mức + lời khuyên)
- `mobile/lib/features/weather/domain/usecases/build_advisories.dart` (gom "Lưu ý hôm nay" — thẻ hiện "🐾 Kato mách bạn")
- `mobile/lib/core/kato/kato_voice.dart` (**KatoVoice** — câu mở đầu giọng mèo Kato theo ngữ cảnh cho alert + digest)
- `mobile/lib/features/alerts/data/alert_state_store.dart` (chống báo trùng — `read()` **luôn `prefs.reload()`** vì SharedPreferences cache riêng theo từng isolate)
- `mobile/lib/features/alerts/domain/usecases/build_weather_alerts.dart` (sinh thông báo sự kiện; lần KHỞI ĐẦU `previousCategory == null` chỉ báo tình hình khi `WeatherSeverity ≥ notice` — chống spam "Nhiều mây" mỗi lần app hồi sinh)
- `mobile/lib/features/alerts/domain/usecases/build_daily_digest.dart` (sinh bản tin hằng ngày)
- `mobile/lib/features/weather/domain/usecases/build_rain_outlook.dart` (outlook mưa cả ngày theo buổi)
- `mobile/lib/features/alerts/data/digest_scheduler.dart` (lập lịch nhiều mốc qua AlarmManager, dải ID động + fallback inexact khi thiếu quyền exact)
- `mobile/lib/features/weather/presentation/widgets/digest_settings_card.dart` (UI cài đặt bản tin — thêm/xóa mốc giờ + cảnh báo quyền exact-alarm, đặt trong màn Thời tiết)
- `mobile/lib/core/background/digest_alarm.dart` (callback alarm: fetch tươi → hiển thị bản tin, re-arm theo index mốc)
- `mobile/lib/core/background/background_location.dart` (`resolveBackgroundCoords` cho isolate nền — log kèm **địa chỉ thực tế** qua `PlaceLabelResolver`, tuổi toạ độ, khoảng đã dịch chuyển)
- `mobile/lib/features/alerts/data/notification_prefs_store.dart` (cài đặt bản tin)
- `mobile/lib/core/notifications/notification_service.dart` (**5 channel** — cảnh báo/ghim ghi chú/nhắc ghi chú/tin mới/**`service_health`** (nhắc bật lại theo dõi liên tục), show/zonedSchedule + details tuỳ biến, BigText)
- `mobile/lib/core/notifications/notification_response_handler.dart` (tap → /notes; action "Đã đọc" chạy isolate nền)
- `mobile/lib/features/notes/data/note_notification_service.dart` (ID slot + buildReminderSlots + sync ghim/lịch + reassert)
- `mobile/lib/core/theme/theme_controller.dart` (cài đặt giao diện + precedence seed)
- `mobile/lib/features/settings/presentation/settings_screen.dart` (màn Settings + guide pin)

---
_Cập nhật lần cuối qua `/sync-docs`. Đừng sửa tay các bảng registry nếu không chạy sync._
