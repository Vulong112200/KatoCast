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
| Thời tiết (weather) | ✅ | — | `features/weather/*` | One Call **4.0** (3 endpoint→chuẩn hoá); offline-first cache Drift; **stale-while-revalidate** (mở app hiện cache ngay, chỉ gọi API khi cache ≥15'); `AnalyzeRain` (neo mọi phép tính vào `now`, lọc điểm dự báo quá khứ, **kết hợp 3 nguồn**: quan trắc `current` đè nowcast khi TRỜI ĐÃ MƯA (`_obsIndicatesRain`) + nowcast khô vẫn đối chiếu hourly có tín hiệu mạnh (mm + pop≥0.6) để không mất cảnh báo sớm, trả `changeAt` timestamp tuyệt đối + **`rainEndsAt`/`durationMinutes`** (nối tiếp hourly khi mưa vượt cửa sổ nowcast) + **`segments`** = diễn biến từng đoạn cường độ (possible/nhỏ/vừa/to, `describeRainCourse` dựng câu "mưa vừa ~17:00–19:00, sau đó mưa nhỏ...") + `probabilityPct` theo pop của **giờ chứa sự kiện** (fallback giờ gần nhất), floor 80% **CHỈ khi ĐANG mưa** — pha "sắp mưa" hiện **pop THẬT** không ép sàn để không thổi phồng %), `DetectEnvChange`; `connectivityStatusProvider` cho badge offline. **Dữ liệu thiếu = null → UI "—"** (trường số `CurrentWeather` nullable, mapper `_toDoubleOrNull/_toIntOrNull`); thiếu `weather[]` → `conditionId=null` → "Không rõ tình hình" (không mặc định nắng). **UI mở rộng:** header địa điểm **đầy đủ** (`Place.fullLabel`), thẻ **CurrentWeatherCard** (UV kèm band màu + mây% + hi/lo + **chi tiết 4.0: điểm sương/áp suất/tầm nhìn/gió giật/hướng gió la bàn**), **HourlyList** (emoji tình hình + °C + **% (ưu tiên pop nowcast 15') + mm mưa** + ghi chú "pop là ước tính OWM"), thẻ **"Lưu ý hôm nay"** (`AdvisoryCard` ← `BuildAdvisories`: tình hình + UV + độ ẩm + gió + mưa) |
| Phân loại tình hình (condition) | ✅ | — | `weather/domain/entities/weather_condition.dart` + `ConditionCard` | nắng/mây/mưa nhỏ-to/dông/bão lớn/lốc + nhãn + lời khuyên + mức độ |
| Thông báo thông minh (alerts) | ✅ | — | `features/alerts/*` + `core/background` + `core/notifications` | Điều phối qua `applyBackgroundTriggers`: **FG bật** (mặc định) → foreground service (CHÍNH, live nhiệt độ + giờ, Doze, `allowWifiLock=false`, re-assert ghim ghi chú mỗi tick) **+ alarm exact chạy SONG SONG làm BACKSTOP** (hồi phục khi FG bị Doze/giết); hủy WorkManager. **FG tắt** → alarm exact + WorkManager (clamp ≥15'). **Chu kỳ tùy chỉnh 5/10/15/30'**. **Khung giờ hoạt động (active hours):** mặc định BẬT giới hạn **5h–21h** (tùy chỉnh hoặc "cả ngày 24/7") — cả 3 lớp trigger `if (isWithinActiveHours(now))` mới `runWeatherCheck`, ngoài khung app ngủ (FG giữ thông báo nhưng không cập nhật; alarm exact **re-arm đúng vào giờ mở khung** `nextActiveWindowStart` thay vì đá CPU dậy mỗi chu kỳ suốt đêm) → mát máy + tiết kiệm quota; digest KHÔNG bị chặn theo khung. Guard quota bám chu kỳ (cache tươi hơn chu kỳ−1' → không gọi API) nên backstop thêm ít nhiệt. **Mở app chạy `runWeatherCheck` ngay** (khởi tạo AlertStateStore + cảnh báo tức thì). 3 nhóm (mưa/tình hình/môi trường), chống spam; nội dung mưa kèm **giờ + % + giờ tạnh/thời lượng + diễn biến từng đoạn cường độ** + **giọng mèo Kato** (`KatoVoice` prepend câu mở đầu); báo lại "Cập nhật" khi mưa đến SỚM ≥15' / DỜI MUỘN ≥45' (bất đối xứng chống spam trôi giờ); **nhắc lại "Sắp mưa: còn ~N phút" khi onset áp sát ≤35'** sau lần báo từ xa (`AlertStateStore` lưu thêm `notifiedAt`; mốc đã báo chỉ ghi đè khi thật sự phát — chống drift); bỏ cảnh báo nếu dữ liệu >45'. ⚠️ **Vuốt tắt app trên OEM diệt tiến trình (Nubia/MyOS, Xiaomi/HyperOS…) = force-stop → hủy mọi alarm + FG service**; chắc chắn nhất là **KHÓA app trong recents 🔒** (hoặc đừng vuốt tắt), thêm **Tự khởi động + Không giới hạn pin** (onboarding dẫn tới, `MainActivity` MethodChannel `katocast/oem` deep-link Autostart đa-hãng). FG service khai báo `android:stopWithTask="false"` (chỉ cứu ca task-removal, không cứu force-stop); alarm backstop tự hồi sinh FG service khi bị Doze giết |
| Bản tin thời tiết hằng ngày (digest) | ✅ | — | `features/alerts/*` (BuildDailyDigest, NotificationPrefsStore, notificationSettingsProvider, **digest_scheduler**) + `core/background/digest_alarm` + `weather/.../build_rain_outlook` + `weather/.../digest_settings_card` | Tự gửi tóm tắt vào **danh sách nhiều mốc giờ TÙY Ý** (thêm/xóa trong **màn Thời tiết** — `DigestSettingsCard`; mặc định 6h30 & 16h30, migrate từ mô hình 2 mốc cũ) qua **`android_alarm_manager_plus`** dùng **`oneShotAt` exact+allowWhileIdle** (KHÔNG `periodic`; mỗi mốc 1 alarm ID **dải động `digestBase + index`**; callback **re-arm theo index**). **Fix không nổ:** kiểm tra `canScheduleExactAlarms` → thiếu quyền thì **fallback `exact:false`** + dòng cảnh báo xin quyền; xin quyền exact-alarm lúc khởi động; `scheduleDigests` idempotent → gọi mỗi chu kỳ tự chữa. **Nút tự chẩn đoán** "Đặt bản tin thử sau 1 phút" (`scheduleDigestTest` → `NotificationIds.digestTest=1099`, callback hiện thông báo xác nhận, không re-arm) để phân biệt lỗi lập lịch vs force-stop OEM. Tại mốc giờ `digestAlarmCallback` **fetch dữ liệu tươi rồi hiển thị**. Nội dung: **câu chào Kato** (sáng/chiều) + **outlook mưa cả ngày theo buổi** + gợi ý mưa tức thời (giờ + **giờ tạnh**) + hi/lo + **UV theo mức**. ⚠️ **AndroidManifest PHẢI khai báo** `AlarmService` + `AlarmBroadcastReceiver` + `RebootBroadcastReceiver` của `android_alarm_manager_plus` (plugin 4.0.x manifest rỗng); thiếu → mọi alarm crash "Component ... does not exist" → không nổ. Đừng xóa. |
| Module 1 — Map & News | ✅ | — | `features/map_news/*` | bản đồ OSM (flutter_map) + lớp mưa OWM; tin tức RSS thời tiết (`MapScreen`, `/map`) |
| Module 2 — Fixed Route POI | ✅ | — | `features/fixed_route/*` | lưu lộ trình (Drift) + quét POI dọc đường qua Overpass/OSM (`RouteScreen`, `/routes`) |
| Ghi chú (notes) | ✅ | — | `features/notes/*` + `core/notifications/notification_response_handler.dart` | Note text/checklist, màu, tìm kiếm, khu "Đã xong"; **ghim sticky** lên thanh thông báo (`ongoing`, sống qua "Xoá tất cả", chỉ gỡ bằng nút **"Đã đọc"** — note giữ nguyên trong app); **hẹn nhắc** một lần/hằng ngày/hằng tuần theo thứ (`zonedSchedule` exact, sống qua reboot); re-assert ghim ở bootstrap + worker 15'; ID scheme `10000 + noteId*16 + slot` (`NotesScreen` `/notes`) |
| Theo dõi thông báo (announcements) | ✅ | **`backend/`** (FastAPI) | `features/announcements/*` + `core/background/announcement_alarm.dart` | **Kiến trúc HYBRID** (mở rộng app → **KatoAssistant**). **Backend** crawl **whitelist nguồn GỐC chính thức** (JLPT: jlpt.jp/jees; MBA: nguồn trường tự cấu hình) → **diff phát hiện mục MỚI** (dedup `content_hash`) → **xác thực** (Claude Haiku phân loại khớp chủ đề + tóm tắt, có rule-based fallback keyword+ngày) → lưu Postgres/SQLite → expose `GET /api/v1/announcements`. **Mobile** poll backend **1 lần/ngày** qua **alarm exact `oneShotAt` tự re-arm** (copy mẫu digest; `announcementCheckCallback`, `scheduleAnnouncementCheck`), lọc mục chưa thấy bằng Drift `seen_announcements`, hiện thông báo **giọng Kato** (`KatoVoice.announcement`) kèm **domain nguồn để kiểm chứng** (chống fake), tap → `/announcements`. Màn **AnnouncementsScreen** (list + bật/tắt + giờ kiểm tra + chọn chủ đề JLPT/MBA + nút **"Kiểm tra tin mới ngay"** `checkAnnouncementsNow`, mở URL nguồn qua url_launcher). Chủ đề generic → thêm bất kỳ (học bổng/visa…) chỉ cần thêm `watch_source`. Dùng chung plugin `android_alarm_manager_plus` với digest nên KHÔNG cần khai báo manifest thêm. **Lịch & mốc hạn:** backend `exam_events` (mốc đăng ký/thi/kết quả, `curated` = lịch chuẩn seed từ nguồn chính thức, `GET /api/v1/events`) — **độ chính xác 3 tầng**: (1) lịch chuẩn seed (JLPT kỳ 7&12/2026, ngày xác thực từ info.jees-jlpt.jp), (2) regex `date_extract` trích ngày trong tin (JP `年月日`/令和 + VN dd/mm + ISO, gán nhãn theo keyword gần nhất) → hiển thị "chưa kiểm chứng", (3) **người dùng sửa/thêm/ghi đè** (Drift `event_overrides`, LUÔN ưu tiên, badge "đã kiểm chứng"). Trạng thái còn hạn/hết hạn **tính client-side** (`computeStatus` → chip màu đỏ/cam/xanh/xám) để luôn tươi. Section "📅 Lịch & hạn" + `EventEditDialog` (4 date picker) trong AnnouncementsScreen. **KHÔNG dùng LLM** cho trích ngày |

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
- Mobile core: `core/kato/kato_voice.dart` (**KatoVoice** — giọng điệu mèo Kato tập trung cho thông báo/UI), `core/config/app_config.dart` (API key + ngưỡng + endpoint dịch vụ ngoài: Overpass mirror, OSM/OWM tile, RSS + `User-Agent`), `core/di/providers.dart` (DI Riverpod hạ tầng), `core/network/` (Dio + connectivity), `core/error/` (failures/exceptions), `core/permissions/`, `core/notifications/`, `core/background/` (foreground service + alarm exact + WorkManager, đều gọi `runWeatherCheck`), `core/database/` (Drift).

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
- `mobile/lib/core/background/background_triggers.dart` (**`applyBackgroundTriggers`** — FG bật: FG + alarm exact backstop song song, hủy WorkManager; FG tắt: alarm + WorkManager)
- `mobile/lib/core/background/weather_check.dart` (**LÕI** kiểm tra thời tiết nền + guard quota bám theo chu kỳ)
- `mobile/lib/core/background/foreground_service.dart` (foreground service `flutter_foreground_task` — chu kỳ đọc từ prefs, `allowWifiLock=false`, re-assert ghim ghi chú mỗi tick)
- `mobile/lib/core/background/weather_alarm.dart` (alarm exact BACKSTOP thường trực — luôn tự re-arm; guard quota khử API trùng với FG; **hồi sinh FG service** nếu prefs bật mà service không chạy)
- `mobile/android/app/src/main/kotlin/.../MainActivity.kt` (MethodChannel `katocast/oem`: deep-link trang Tự khởi động/Autostart đa-hãng + battery settings)
- `mobile/lib/core/background/background_worker.dart` (WorkManager backstop clamp ≥15' → gọi `runWeatherCheck`, có `cancel()`)
- `mobile/lib/core/background/background_prefs.dart` (bật/tắt foreground service + chu kỳ nền 5/10/15/30' + **khung giờ hoạt động**: `isWithinActiveHours`/`nextActiveWindowStart` — gate 3 lớp trigger, hỗ trợ khung qua nửa đêm)
- `mobile/lib/features/weather/domain/usecases/analyze_rain.dart` (logic mưa cốt lõi — quan trắc đè nowcast + `changeAt` + `rainEndsAt` + `segments` diễn biến)
- `mobile/lib/features/weather/domain/entities/uv_advice.dart` (UV → mức + lời khuyên)
- `mobile/lib/features/weather/domain/usecases/build_advisories.dart` (gom "Lưu ý hôm nay" — thẻ hiện "🐾 Kato mách bạn")
- `mobile/lib/core/kato/kato_voice.dart` (**KatoVoice** — câu mở đầu giọng mèo Kato theo ngữ cảnh cho alert + digest)
- `mobile/lib/features/alerts/domain/usecases/build_weather_alerts.dart` (sinh thông báo sự kiện)
- `mobile/lib/features/alerts/domain/usecases/build_daily_digest.dart` (sinh bản tin hằng ngày)
- `mobile/lib/features/weather/domain/usecases/build_rain_outlook.dart` (outlook mưa cả ngày theo buổi)
- `mobile/lib/features/alerts/data/digest_scheduler.dart` (lập lịch nhiều mốc qua AlarmManager, dải ID động + fallback inexact khi thiếu quyền exact)
- `mobile/lib/features/weather/presentation/widgets/digest_settings_card.dart` (UI cài đặt bản tin — thêm/xóa mốc giờ + cảnh báo quyền exact-alarm, đặt trong màn Thời tiết)
- `mobile/lib/core/background/digest_alarm.dart` (callback alarm: fetch tươi → hiển thị bản tin, re-arm theo index mốc)
- `mobile/lib/core/background/background_location.dart` (resolveBackgroundCoords cho isolate nền)
- `mobile/lib/features/alerts/data/notification_prefs_store.dart` (cài đặt bản tin)
- `mobile/lib/core/notifications/notification_service.dart` (3 channel, show/zonedSchedule + details tuỳ biến, BigText)
- `mobile/lib/core/notifications/notification_response_handler.dart` (tap → /notes; action "Đã đọc" chạy isolate nền)
- `mobile/lib/features/notes/data/note_notification_service.dart` (ID slot + buildReminderSlots + sync ghim/lịch + reassert)
- `mobile/lib/core/theme/theme_controller.dart` (cài đặt giao diện + precedence seed)
- `mobile/lib/features/settings/presentation/settings_screen.dart` (màn Settings + guide pin)

---
_Cập nhật lần cuối qua `/sync-docs`. Đừng sửa tay các bảng registry nếu không chạy sync._
