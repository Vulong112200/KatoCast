# KatoCast — Mobile (Flutter)

Ứng dụng dự báo thời tiết cá nhân hóa, độ chính xác cao, cảnh báo mưa chủ động.

## Kiến trúc (Clean Architecture, feature-first)

Mỗi feature tách 3 lớp rõ ràng — dễ mở rộng mà không đụng core:

```
lib/
├── core/        # config, error, network, database (Drift), permissions,
│                # notifications, background (WorkManager), di, router
├── shared/      # error_handler + widget tái dùng
└── features/
    ├── location/   # định vị (geolocator)        — domain / data / presentation
    ├── weather/    # thời tiết + phân tích mưa    — domain / data / presentation
    ├── alerts/     # sinh thông báo cá nhân hóa
    ├── map_news/   # MODULE 1 (Phase 2) — STUB
    └── fixed_route/# MODULE 2 (Phase 2) — lưu lộ trình OK, quét POI là STUB
```

- **Data Layer**: `data/datasources` (remote Dio + local Drift) + `data/models` (mapper JSON→entity).
- **Repository Layer**: `domain/repositories` (interface) + `data/repositories/*_impl` (offline-first, trả `Either<Failure, T>`).
- **UI Layer**: `presentation/providers` (Riverpod) + `screens/widgets`. Logic thuần ở `domain/usecases`.

> Khi nhúng backend FastAPI sau này: chỉ cần thêm 1 remote datasource mới, UI/usecase không đổi.

## Tính năng Phase 1

| | Mô tả |
|---|---|
| Định vị | `geolocator` — current + stream (distanceFilter 200m để tiết kiệm pin) |
| Thời tiết | OpenWeatherMap **One Call 4.0**: nhiệt độ, độ ẩm, UV, mưa, **nowcast 15'** + **hourly**; datasource gọi 3 endpoint timeline rồi chuẩn hoá |
| Logic mưa | `AnalyzeRain`: phát hiện bắt đầu/kết thúc mưa từ `minutely` (chống nhiễu), fallback `hourly` |
| Phân loại tình hình | `WeatherCondition.classify`: nắng / ít mây / nhiều mây / u ám / sương mù / mưa nhỏ-vừa-to-rất to / dông / **bão lớn** / lốc xoáy / tuyết — kèm nhãn + lời khuyên + mức độ |
| Thông báo | WorkManager 15' → `flutter_local_notifications`; 3 nhóm: (1) thời điểm mưa, (2) tình hình thời tiết, (3) thay đổi nhiệt/ẩm — cá nhân hóa, chống spam (chỉ phát khi trạng thái đổi) |
| Offline | fallback cache Drift + badge "dữ liệu lúc …" |
| Quyền | từ chối vị trí/thông báo → UI hướng dẫn, không crash |

## Setup & chạy

1. Cài Flutter SDK + Android toolchain → `flutter doctor`.
2. Tạo API key tại <https://openweathermap.org/api> và **đăng ký gói "One Call by Call" (API 3.0)** (miễn phí 1000 calls/ngày, cần thêm thẻ để kích hoạt hạn mức).
3. Copy `env.json.example` → `env.json`, điền key (file `env.json` đã được .gitignore).
4. Cài dependency & sinh code:
   ```bash
   cd mobile
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
5. Chạy:
   ```bash
   flutter run --dart-define-from-file=env.json
   ```
   (hoặc `flutter run --dart-define=OWM_API_KEY=<key>`)
6. Cấp quyền **Vị trí** + **Thông báo** khi app hỏi.

## Quyền (Android)

Đã khai báo trong `android/app/src/main/AndroidManifest.xml`:
`INTERNET`, `ACCESS_FINE/COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`,
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`.
`minSdk = 23`, bật **core library desugaring** (cho flutter_local_notifications).

## Test

```bash
flutter test                 # unit test logic mưa + sinh thông báo
flutter analyze              # lint
```

- Test background nhanh: mở app → nút 🔔 trên AppBar (`BackgroundScheduler.runOnceNow`).
- Test offline: bật Airplane mode → app hiển thị cache + badge.

## One Call 4.0 (đang dùng)

App target **One Call 4.0** (`AppConfig.owmApiVersion = '4.0'`). 4.0 tách dữ
liệu thành nhiều endpoint timeline, nên `WeatherRemoteDataSource` gọi **song
song 3 endpoint** rồi **chuẩn hoá về shape gộp** (current + minutely + hourly):

| Endpoint 4.0 | Vai trò | Chuẩn hoá thành |
|---|---|---|
| `/data/4.0/onecall/current` | thời tiết hiện tại (`data[0]`) | `current` |
| `/data/4.0/onecall/timeline/15min` | nowcast 15 phút | `minutely` (mỗi mốc cách 15') |
| `/data/4.0/onecall/timeline/1h` | dự báo theo giờ | `hourly` |

Nhờ chuẩn hoá ở **data layer**, `WeatherMapper`, cache Drift, repository, các
usecase và toàn bộ UI **không phải đổi** — đúng tinh thần Clean Architecture.
`AnalyzeRain` tính số phút theo **mốc thời gian** nên đúng cho cả độ phân giải
1 phút (3.0) lẫn 15 phút (4.0).

> ⚠️ **Hạn mức:** mỗi lần refresh = **3 lượt gọi API**. Free tier OWM 1000
> calls/ngày → background 15' (~96 lần/ngày × 3 = 288) + foreground vẫn an toàn,
> nhưng cân nhắc nếu tăng tần suất.
>
> 🔑 **Key:** tài khoản OWM phải đăng ký sản phẩm **One Call API 4.0**.
> Muốn quay lại 3.0: đổi `AppConfig.owmApiVersion = '3.0'` và khôi phục
> `WeatherRemoteDataSource` bản gọi 1 endpoint `/onecall` (xem lịch sử git).

## iOS (Phase sau)

Thêm vào `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription`, và `UIBackgroundModes`
(`fetch`, `location`). Lưu ý iOS giới hạn background fetch (~OS quyết định).
