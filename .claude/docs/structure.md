# Structure — Cây thư mục & vai trò file

> Cập nhật qua `/sync-docs`. Mỗi entry là 1 file/thư mục + comment ngắn mô tả mục đích.
> Dự án mới: cấu trúc dưới đây là **chuẩn dự kiến** (target). Khi tạo file thật, thêm/sửa entry cho khớp.

## Backend (`backend/`)

```
backend/
├── app/
│   ├── main.py              # FastAPI app entrypoint, mount router, middleware
│   ├── api/
│   │   ├── router.py        # gom & register tất cả router v1
│   │   └── v1/              # mỗi file = 1 nhóm endpoint (vd auth.py, users.py)
│   ├── services/            # business logic, 1 service/feature
│   ├── repositories/        # data access thuần (CRUD + soft delete)
│   ├── models/              # SQLAlchemy models (1 file/table hoặc nhóm)
│   ├── schemas/             # Pydantic v2 DTO (Create/Read/Update)
│   └── core/
│       ├── config.py        # Settings (env vars), DATABASE_URL, REDIS_URL
│       ├── security.py      # JWT, hash password
│       └── deps.py          # get_current_active_user, get_db session
├── alembic/                 # migrations (versions/ — KHÔNG sửa file đã apply)
├── .env.example             # mẫu biến môi trường
└── DB_schema.sql            # snapshot schema thực tế (để đối chiếu models)
```

## Mobile (`mobile/`)

> Thực tế (Phase 1, client-only). Mỗi feature theo Clean Architecture: `domain/` (entities, repositories interface, usecases) · `data/` (datasources, models, repositories impl) · `presentation/` (providers, screens, widgets).

```
mobile/
├── lib/
│   ├── main.dart                 # ProviderScope, init timezone (+ setLocalLocation) + AndroidAlarmManager, notif/permission/background, prompt pin lần đầu, lập lịch digest, AppLifecycleListener (resume→refresh), MaterialApp.router
│   ├── core/
│   │   ├── app_router.dart        # GoRouter: '/' Weather · '/map' Map&News · '/routes' RouteScreen · '/settings' Settings
│   │   ├── config/app_config.dart # API key (--dart-define) + ngưỡng mưa/pin/chu kỳ
│   │   ├── di/providers.dart      # DI Riverpod hạ tầng (permission, network, dio, db, notif)
│   │   ├── theme/                 # theme_palettes · weather_theme · app_theme · theme_controller (cá nhân hóa giao diện)
│   │   ├── database/app_database.dart  # Drift DB (WeatherCache, FixedRoutePoints) [+ .g.dart]
│   │   ├── network/
│   │   │   ├── api_client.dart     # Dio + interceptor map lỗi → exceptions
│   │   │   └── network_info.dart   # connectivity_plus → isOnline
│   │   ├── error/
│   │   │   ├── failures.dart        # sealed Failure (Network/Server/Cache/Permission/Unexpected)
│   │   │   └── exceptions.dart      # exceptions tầng data
│   │   ├── permissions/permission_service.dart   # geolocator + permission_handler
│   │   ├── notifications/notification_service.dart # flutter_local_notifications: show (BigText) + scheduleDaily/cancel (zonedSchedule, fallback) + IDs
│   │   └── background/                        # background_worker (WorkManager 15' + alert) · background_location (resolveBackgroundCoords) · digest_alarm (AlarmManager fetch tươi → bản tin)
│   ├── shared/
│   │   ├── utils/error_handler.dart   # extractUserMessage(e)
│   │   └── widgets/                    # AppErrorWidget, LoadingWidget, PermissionDeniedWidget, AppDrawer (điều hướng)
│   └── features/
│       ├── location/   # domain(Coordinates, Place, repo) · data(datasource geolocator+geocoding, repo impl, LastLocationStore) · presentation(providers: current/stream/place)
│       ├── settings/   # presentation(SettingsScreen): chọn theme/bảng màu/Material You/đổi-màu-theo-thời-tiết + quyền thông báo + guide pin
│       ├── weather/    # domain(entities, usecases AnalyzeRain/DetectEnvChange/BuildRainOutlook) · data(model mapper, datasources, repo) · presentation(providers, WeatherScreen, widgets)
│       ├── alerts/     # domain(WeatherAlert, BuildWeatherAlerts, BuildDailyDigest) · data(AlertStateStore, NotificationPrefsStore, digest_scheduler→AlarmManager) · presentation(notificationSettingsProvider)
│       ├── map_news/   # MODULE 1: NewsItem · RssDataSource (xml) · NewsRepositoryImpl · MapScreen (flutter_map + lớp mưa OWM + tin RSS)
│       └── fixed_route/# MODULE 2: RoutePoint/Poi · RouteLocalDataSource (Drift) · OverpassDataSource · PoiRepositoryImpl · RouteScreen (flutter_map) · poi_visuals
├── assets/icon/        # app_icon.png (logo) — nguồn sinh launcher icon & splash
├── test/               # analyze_rain_test · build_weather_alerts_test · weather_condition_test · build_rain_outlook_test
├── env.json.example    # mẫu API key (copy → env.json, đã .gitignore)
└── pubspec.yaml        # + flutter_launcher_icons / flutter_native_splash config (icon/splash từ logo)
```

## Root project (`D:\Tools\KatoCast\`)

```
KatoCast/
├── CLAUDE.md                # tài liệu gốc — đọc đầu tiên
├── .claude/
│   ├── settings.json        # permissions + Stop-hook nhắc sync-docs
│   ├── docs/                # structure.md · features.md · callflows.md
│   ├── skills/sync-docs/    # skill cập nhật docs
│   └── hooks/               # remind-sync-docs.sh
├── backend/                 # (xem trên)
└── mobile/                  # (xem trên)
```
