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
│   ├── main.dart                 # ProviderScope, init timezone/notif/permission/background, MaterialApp.router
│   ├── core/
│   │   ├── app_router.dart        # GoRouter (route '/' → WeatherScreen)
│   │   ├── config/app_config.dart # API key (--dart-define) + ngưỡng mưa/pin/chu kỳ
│   │   ├── di/providers.dart      # DI Riverpod hạ tầng (permission, network, dio, db, notif)
│   │   ├── database/app_database.dart  # Drift DB (WeatherCache, FixedRoutePoints) [+ .g.dart]
│   │   ├── network/
│   │   │   ├── api_client.dart     # Dio + interceptor map lỗi → exceptions
│   │   │   └── network_info.dart   # connectivity_plus → isOnline
│   │   ├── error/
│   │   │   ├── failures.dart        # sealed Failure (Network/Server/Cache/Permission/Unexpected)
│   │   │   └── exceptions.dart      # exceptions tầng data
│   │   ├── permissions/permission_service.dart   # geolocator + permission_handler
│   │   ├── notifications/notification_service.dart # flutter_local_notifications + channel + IDs
│   │   └── background/background_worker.dart       # WorkManager: scheduler + callbackDispatcher
│   ├── shared/
│   │   ├── utils/error_handler.dart   # extractUserMessage(e)
│   │   └── widgets/                    # AppErrorWidget, LoadingWidget, PermissionDeniedWidget
│   └── features/
│       ├── location/   # domain(Coordinates, repo) · data(datasource, repo impl) · presentation(providers)
│       ├── weather/    # domain(entities, usecases AnalyzeRain/DetectEnvChange) · data(model mapper, datasources, repo) · presentation(providers, WeatherScreen, widgets)
│       ├── alerts/     # domain(WeatherAlert, BuildWeatherAlerts) · data(AlertStateStore)
│       ├── map_news/   # MODULE 1 (Phase 2 STUB): NewsRepository + NewsRepositoryStub
│       └── fixed_route/# MODULE 2: RoutePoint/Poi · RouteLocalDataSource (Drift) · PoiRepositoryStub
├── test/               # analyze_rain_test.dart · build_weather_alerts_test.dart
├── env.json.example    # mẫu API key (copy → env.json, đã .gitignore)
└── pubspec.yaml
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
