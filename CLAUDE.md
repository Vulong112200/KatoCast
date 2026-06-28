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

> 📌 Phase 1 (mobile, client-only) đã hoàn thiện: định vị + thời tiết One Call 3.0 + thông báo thông minh, kèm stub Phase 2. Backend chưa dựng. Cập nhật các bảng "Registry" bên dưới qua `/sync-docs` khi code đổi.

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
| Định vị (location) | ✅ | — | `features/location/*` (geolocator + geocoding) | current + stream, distanceFilter 200m; reverse geocoding → tên địa danh (`Place`, `currentPlaceProvider`) hiển thị trên AppBar |
| Giao diện & cá nhân hóa (theme) | ✅ | — | `core/theme/*` + `features/settings/*` | Sáng/Tối/Hệ thống + bảng màu chọn sẵn + Material You (dynamic_color) + đổi màu theo thời tiết; lưu SharedPreferences; màn Settings (+ guide pin) |
| Thời tiết (weather) | ✅ | — | `features/weather/*` | One Call **4.0** (3 endpoint→chuẩn hoá); offline-first cache Drift; `AnalyzeRain`, `DetectEnvChange` |
| Phân loại tình hình (condition) | ✅ | — | `weather/domain/entities/weather_condition.dart` + `ConditionCard` | nắng/mây/mưa nhỏ-to/dông/bão lớn/lốc + nhãn + lời khuyên + mức độ |
| Thông báo thông minh (alerts) | ✅ | — | `features/alerts/*` + `core/background` + `core/notifications` | WorkManager 15', 3 nhóm (mưa/tình hình/môi trường), cá nhân hóa, chống spam |
| Module 1 — Map & News | ✅ | — | `features/map_news/*` | bản đồ OSM (flutter_map) + lớp mưa OWM; tin tức RSS thời tiết (`MapScreen`, `/map`) |
| Module 2 — Fixed Route POI | ✅ | — | `features/fixed_route/*` | lưu lộ trình (Drift) + quét POI dọc đường qua Overpass/OSM (`RouteScreen`, `/routes`) |

> Status: 📋 planned · 🚧 in progress · ✅ done

## 4. API Endpoints Summary

> Client-only — KHÔNG có backend endpoint. App tiêu thụ API ngoài:

| Group | Method | Path | Mô tả |
|-------|--------|------|-------|
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/current` | thời tiết hiện tại (`data[0]`) |
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/timeline/15min` | nowcast 15' → chuẩn hoá thành `minutely` |
| OpenWeatherMap 4.0 | GET | `/data/4.0/onecall/timeline/1h` | dự báo giờ → `hourly` |
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

## 6. Shared Utilities

- Backend: `backend/app/core/` (config, security, deps). _(chưa có — Phase 1 client-only)_
- Mobile shared: `mobile/lib/shared/utils/error_handler.dart` → `extractUserMessage`; widgets `AppErrorWidget`, `LoadingWidget`, `PermissionDeniedWidget`.
- Mobile core: `core/config/app_config.dart` (API key + ngưỡng + endpoint dịch vụ ngoài: Overpass mirror, OSM/OWM tile, RSS + `User-Agent`), `core/di/providers.dart` (DI Riverpod hạ tầng), `core/network/` (Dio + connectivity), `core/error/` (failures/exceptions), `core/permissions/`, `core/notifications/`, `core/background/` (WorkManager), `core/database/` (Drift).

## 7. Quy trình làm việc & công cụ

| Khi cần | Dùng |
|---------|------|
| Thêm feature mới (BE/mobile) | `/add-feature` |
| Debug backend FastAPI | `/debug-backend` |
| Debug Flutter mobile | `/debug-mobile` |
| **Cập nhật docs sau khi sửa code** | **`/sync-docs`** |

### File quan trọng nhất (cập nhật khi project lớn lên)
- `backend/app/main.py`, `backend/app/api/router.py`, `backend/app/core/config.py` _(chưa có)_
- `mobile/lib/main.dart`, `mobile/lib/core/app_router.dart`, `mobile/lib/core/network/api_client.dart`
- `mobile/lib/core/config/app_config.dart` (API key + ngưỡng tinh chỉnh)
- `mobile/lib/core/background/background_worker.dart` (WorkManager entry-point)
- `mobile/lib/features/weather/domain/usecases/analyze_rain.dart` (logic mưa cốt lõi)
- `mobile/lib/features/alerts/domain/usecases/build_weather_alerts.dart` (sinh thông báo)
- `mobile/lib/core/theme/theme_controller.dart` (cài đặt giao diện + precedence seed)
- `mobile/lib/features/settings/presentation/settings_screen.dart` (màn Settings + guide pin)

---
_Cập nhật lần cuối qua `/sync-docs`. Đừng sửa tay các bảng registry nếu không chạy sync._
