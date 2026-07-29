# Structure — Cây thư mục & vai trò file

> Cập nhật qua `/sync-docs`. Mỗi entry là 1 file/thư mục + comment ngắn mô tả mục đích.
> Dự án mới: cấu trúc dưới đây là **chuẩn dự kiến** (target). Khi tạo file thật, thêm/sửa entry cho khớp.

## Backend (`backend/`) — KatoAssistant (theo dõi thông báo)

> FastAPI async · SQLAlchemy 2.0 · Alembic. Crawl whitelist nguồn GỐC → diff (`content_hash`) → verify (Claude Haiku/rule-based) → REST cho mobile poll 1 lần/ngày. Dev chạy SQLite (mặc định), prod Postgres (asyncpg). Xem `backend/README.md`.

```
backend/
├── app/
│   ├── main.py                  # FastAPI entrypoint, CORS, lifespan create_all (dev), /health
│   ├── api/
│   │   ├── router.py            # gom router v1 (prefix /api/v1): announcements + events
│   │   ├── v1/announcements.py  # GET /announcements · GET/POST /watch-sources · POST /crawl
│   │   └── v1/events.py         # GET /events?topic= (lịch có cấu trúc exam_events)
│   ├── services/
│   │   ├── crawl_service.py     # LÕI: fetch(httpx)→parse(bs4, bytes tránh mojibake)→diff content_hash→verify→set extracted_dates→lưu mục MỚI
│   │   ├── verify_service.py    # Claude Haiku phân loại+tóm tắt (không key→rule-based keyword+ngày; MBA cờ "không GMAT")
│   │   └── date_extract.py      # regex trích ngày JP(年月日/令和)/VN(dd/mm)/ISO + gán nhãn (registration/exam/deadline/result) theo keyword gần nhất — KHÔNG LLM
│   ├── repositories/            # announcement_repo.py (dedup hash, list_since) + WatchSourceRepository · exam_event_repo.py (list, upsert_by_label)
│   ├── models/                  # SQLAlchemy: announcement.py (+extracted_dates) · watch_source.py · exam_event.py (import gom ở __init__)
│   ├── schemas/                 # Pydantic v2: announcement.py (AnnouncementRead +extracted_dates, WatchSource*) · exam_event.py (ExamEventRead/Create)
│   ├── db/                      # base.py (DeclarativeBase) · session.py (async engine + get_session)
│   ├── core/config.py           # Settings (DATABASE_URL tự ép →asyncpg, ANTHROPIC_API_KEY, VERIFY_MODEL, CORS, UA)
│   └── jobs/
│       ├── daily_crawl.py       # cron entrypoint: python -m app.jobs.daily_crawl [topic]
│       ├── seed_sources.py      # nạp whitelist nguồn JLPT chính thức (MBA: cấu hình thêm)
│       └── seed_events.py       # seed lịch CHUẨN JLPT kỳ 7&12/2026 (ngày xác thực từ info.jees-jlpt.jp), idempotent
├── alembic/ (env.py + versions/0001_initial.py, 0002_events_and_extracted_dates.py)  # migrations
├── tests/                       # test_crawl_service.py (diff/dedup HTML fixture) · test_date_extract.py (regex ngày JP/VN)
├── requirements.txt · pytest.ini · alembic.ini · .env.example · README.md
└── Dockerfile · .dockerignore · render.yaml  # deploy Render (Blueprint: Postgres+web+cron; preDeploy: alembic upgrade+seed)
```

## Mobile (`mobile/`)

> Thực tế (Phase 1, client-only). Mỗi feature theo Clean Architecture: `domain/` (entities, repositories interface, usecases) · `data/` (datasources, models, repositories impl) · `presentation/` (providers, screens, widgets).

```
mobile/
├── lib/
│   ├── main.dart                 # ProviderScope, init timezone + AndroidAlarmManager, notif/permission + xin exact-alarm, khởi động nền qua applyBackgroundTriggers, nhắc pin, lập lịch digest, CHẠY runWeatherCheck khi mở app (cảnh báo tức thì), onboarding Tự-khởi-động 1 lần, AppLifecycleListener (resume→refresh), MaterialApp.router
│   ├── core/
│   │   ├── app_router.dart        # GoRouter: '/' Weather · '/map' Map&News · '/routes' RouteScreen · '/notes' (+/notes/edit) Notes · '/announcements' Theo dõi thông báo · '/settings' Settings
│   │   ├── config/app_config.dart # API key (--dart-define) + ngưỡng mưa/pin/chu kỳ + digestDefaultTimes + digestMaxSlots + backendBaseUrl (KATO_BACKEND_URL) + announcementTopics/CheckDefaultMinutes
│   │   ├── di/providers.dart      # DI Riverpod hạ tầng (permission, network, dio, db, notif)
│   │   ├── theme/                 # theme_palettes (7 bảng màu chọn sẵn, gồm "Nâu Kato 🐾" tông Bengal) · weather_theme · app_theme · theme_controller (cá nhân hóa giao diện)
│   │   ├── kato/kato_voice.dart   # KatoVoice — giọng điệu mèo Kato tập trung: câu mở đầu ngắn theo ngữ cảnh (rainIncoming/raining/rainStopping/cleared/envChange/digest/announcement), biến thể chọn theo seed (thuần, test được)
│   │   ├── database/app_database.dart  # Drift DB v4 (WeatherCache, FixedRoutePoints, Notes, NoteItems, SeenAnnouncements, EventOverrides) + MigrationStrategy (v3→v4 event_overrides) [+ .g.dart]
│   │   ├── diagnostics/            # NHẬT KÝ HOẠT ĐỘNG (chẩn đoán chạy nền)
│   │   │   ├── app_log.dart        # AppLog static (mọi isolate, không Riverpod): ghi JSONL vào <appDocs>/logs/kato.log qua FileMode.writeOnlyAppend — CỐ TÌNH KHÔNG dùng Drift để log được cả lúc DB bị khoá; i/w/e + rotation 512KB×2 file + readAll (prune 7 ngày/5000 dòng) + clear/exportText/flush + debugOverrideDirectory (test)
│   │   │   ├── log_entry.dart      # LogEntry thuần + tryParse chịu lỗi (dòng ghi dở → bỏ, không sập trang) + toDisplayLine/dayKey; LogLevel {info,warn,error}; LogSource {fg,alarm,beat,worker,digest,announce,ui} + label/backgroundSources
│   │   │   ├── log_tags.dart       # LogTags chuẩn: cycle/window/loc/source/fetch/analyze/notify/skip/arm/lock/service/db/digest/announce/boot
│   │   │   └── log_health.dart     # LogHealth.from(entries) — SUY RA tình trạng từ chính nhật ký (không có store thứ hai): lastCycleAt/lastFetchOkAt/lastNotifyAt/nextAlarmAt/lastError + thống kê 24h + longestGap24h (phát hiện "ngủ mất mấy tiếng"; bỏ đoạn đầu cửa sổ nếu nhật ký chưa trải hết 24h để không báo động giả)
│   │   ├── network/
│   │   │   ├── api_client.dart     # Dio + interceptor map lỗi → exceptions + close() (BẮT BUỘC gọi ở isolate nền: mỗi chu kỳ tạo client mới, không đóng thì rò HttpClient + pool socket)
│   │   │   └── network_info.dart   # connectivity_plus → isOnline
│   │   ├── error/
│   │   │   ├── failures.dart        # sealed Failure (Network/Server/Cache/Permission/Unexpected)
│   │   │   └── exceptions.dart      # exceptions tầng data
│   │   ├── permissions/permission_service.dart   # geolocator + permission_handler (vị trí/thông báo/pin + isExactAlarmGranted/requestExactAlarmPermission + openAutoStartSettings qua MethodChannel katocast/oem)
│   │   ├── notifications/
│   │   │   ├── notification_service.dart          # flutter_local_notifications: 4 channel (weather/note ghim/note nhắc/announcements), show/showWithDetails/showAnnouncement (BigText) + scheduleDaily/zonedScheduleWithDetails/cancel + getLaunchDetails + IDs (announcementBase 2000)
│   │   │   └── notification_response_handler.dart # onNotificationTap (payload announcement:→/announcements, note→/notes) + onNotificationActionBackground (isolate riêng: "Đã đọc" → unpin DB + re-sync lịch)
│   │   └── background/                        # background_triggers (applyBackgroundTriggers: FG + alarm exact + WorkManager CÙNG bật — CycleLock đảm bảo chỉ 1 chu kỳ chạy nên nhiều lớp = nhiều đường hồi phục; alarm arm LỆCH NỬA CHU KỲ so với FG để làm backstop đúng nghĩa thay vì đồng pha) · cycle_lock (CycleLock: lock BẰNG FILE <appDocs>/bg_cycle.lock, owner+timestamp, staleAfter 3' tự chiếm lại; KHÔNG dùng SharedPreferences vì cache riêng theo isolate → vô dụng cho loại trừ lẫn nhau; tryAcquire/release/runGuarded + debugOverrideDirectory) · alarm_schedule_guard (AlarmScheduleGuard dùng CHUNG cho digest & poll tin: claimSchedule throttle 1h có prefs.reload, justPassed grace 20', nextInstanceOf) · weather_check (LÕI runWeatherCheck({source, db}) + guard quota + purge cache 1 lần/NGÀY trong try + log đầy đủ mọi quyết định) · foreground_service (chu kỳ từ prefs, allowWifiLock=false; TOÀN BỘ phần dùng DB trong CycleLock; ngoài khung giờ vẫn updateService "đang nghỉ" thay vì đóng băng text cũ; startWeatherForegroundService({allowRestart}) — nền dùng false để không reset pha FG) · weather_alarm (BACKSTOP luôn re-arm + kWeatherAlarmNextMsKey/weatherAlarmChainStatus cho watchdog; kNightHopInterval 2h — ban đêm nhảy từng chặng thay vì treo cả đêm trên 1 alarm; hồi sinh FG chỉ khi đã chết) · background_worker (WorkManager LUÔN bật — lịch do JobScheduler của HĐH giữ nên sống sót khi chuỗi one-shot đứt; chỉ dựng lại alarm khi weatherAlarmChainStatus().overdue) · background_prefs (bật/tắt FG + intervalMinutes 5/10/15/30 + khung giờ hoạt động: isWithinActiveHours/nextActiveWindowStart) · background_location (resolveBackgroundCoords({source}) + log toạ độ/nguồn/tuổi) · digest_alarm (oneShotAt fetch tươi → bản tin trong CycleLock, re-arm theo index; digestTest riêng) · announcement_alarm (poll backend tự re-arm trong CycleLock; markSeen TRƯỚC show + unmarkSeen bù trừ khi show lỗi; ID thông báo theo BỘ ĐẾM XOAY VÒNG thay cho remoteId%span)
│   ├── shared/
│   │   ├── utils/error_handler.dart   # extractUserMessage(e)
│   │   └── widgets/                    # AppErrorWidget (😿 + cloud_off), LoadingWidget (🐱 + spinner), PermissionDeniedWidget, AppDrawer (điều hướng, header mascot 🐱)
│   └── features/
│       ├── location/   # domain(Coordinates, Place +thoroughfare, repo) · data(datasource geolocator+geocoding, nominatim_datasource reverse OSM, repo impl ưu tiên Nominatim→fallback plugin, LastLocationStore) · presentation(providers: current/stream/place/nominatimDS)
│       ├── settings/   # presentation(SettingsScreen + providers/background_settings_provider: state BackgroundSettings {foregroundEnabled, intervalMinutes, activeAllDay, activeStartMinutes, activeEndMinutes}): theme/bảng màu/Material You/đổi-màu + quyền thông báo + công tắc theo-dõi-liên-tục (FG) + bộ chọn chu kỳ 5/10/15/30' (_IntervalSetting) + khung giờ hoạt động (_ActiveHoursSetting: switch cả-ngày + 2 time-picker bắt đầu/kết thúc) + guide pin + nút "Bật Tự khởi động" (openAutoStartSettings) + **"Nhật ký hoạt động" → /diagnostics** + mục "Về chú mèo Kato" (dialog kể chuyện tên app) (phần cài đặt bản tin ĐÃ chuyển sang màn Weather)
│       ├── weather/    # domain(entities +UvAdvice; rain_status: RainPhase + RainIntensity/RainSegment + describeRainCourse; usecases AnalyzeRain +rainEndsAt/segments + quan trắc đè nowcast + nowcast khô đối chiếu hourly / DetectEnvChange / BuildRainOutlook / BuildAdvisories) · data(model mapper, datasources, repo) · presentation(providers, WeatherScreen +header địa điểm đầy đủ, widgets: current_card +UV/mây/hi-lo, advisory_card "🐾 Kato mách bạn", digest_settings_card "Bản tin hằng ngày" (nhiều mốc giờ tùy ý + cảnh báo quyền exact-alarm + gửi thử ngay + test chạy nền 1'), condition/hourly/rain_banner +diễn biến đoạn)
│       ├── alerts/     # domain(WeatherAlert, BuildWeatherAlerts +giờ tạnh/thời lượng/diễn biến đoạn + Cập nhật bất đối xứng sớm15'/muộn45' + nhắc lại onset ≤35', BuildDailyDigest +UV band, nhận now) · data(AlertStateStore +notifiedAt — chỉ chốt mốc khi thật sự phát, NotificationPrefsStore: DigestPrefs {enabled, List<int> times} + migrate key cũ, digest_scheduler→AlarmManager oneShotAt dải ID động + fallback inexact) · presentation(notificationSettingsProvider: addTime/removeTime/updateTime)
│       ├── map_news/   # MODULE 1: NewsItem · RssDataSource (xml) · NewsRepositoryImpl · MapScreen (flutter_map + lớp mưa OWM + tin RSS)
│       ├── fixed_route/# MODULE 2: RoutePoint/Poi · RouteLocalDataSource (Drift) · OverpassDataSource · PoiRepositoryImpl · RouteScreen (flutter_map) · poi_visuals
│       ├── diagnostics/  # NHẬT KÝ HOẠT ĐỘNG (chỉ presentation — dữ liệu từ core/diagnostics): providers/diagnostics_providers (logEntries/logHealth/runtimeStatus + logFilter LogFilter{all,background,notifications,errors} + logSearch → filteredLogEntries) · screens/DiagnosticsScreen (/diagnostics: thẻ "Tình trạng" + thẻ "Cấu hình & quyền" + filter chip + tìm kiếm + list nhóm theo ngày màu theo mức + Copy toàn bộ/Xoá nhật ký)
│       ├── notes/      # Ghi chú: domain(Note/NoteItem/NoteRepeat) · data(NoteLocalDataSource Drift, note_notification_service: slot ID + buildReminderSlots + sync ghim/lịch + reassert) · presentation(notesControllerProvider, NotesScreen, NoteEditScreen, note_colors)
│       └── announcements/  # Theo dõi thông báo + Lịch & mốc hạn (JLPT/MBA): domain(Announcement +fromJson +extractedDates/ExtractedDate; ExamEvent +fromJson/copyWith; event_status.computeStatus → EventStatus {summaryLabel, StatusLevel, lines} tính còn hạn/hết hạn client-side) · data(AnnouncementRemoteDataSource + AnnouncementRepository dedup Drift seen_announcements + announcement_scheduler; EventRemoteDataSource GET /events, EventRepository merge backend+Drift event_overrides bản-sửa-tay-ưu-tiên + CRUD override; AnnouncementPrefsStore {enabled,checkMinutes,topics}) · presentation(announcements_providers +eventRepository/examEvents, AnnouncementsScreen list+cài đặt+nút test + section "📅 Lịch & hạn" chip màu trạng thái, widgets/event_edit_dialog 4 date-picker Sửa/Thêm mốc)
├── assets/icon/        # app_icon.png (logo) — nguồn sinh launcher icon & splash
├── test/               # app_log_test (ghi/đọc, dòng hỏng bị bỏ, retention, rotation, cắt maxEntries, clear/export + LogEntry.tryParse + LogHealth thống kê/nextAlarmAt/longestGap + ca "nhật ký chưa trải 24h") · cycle_lock_test (chặn lượt 2, chiếm lại lock quá hạn, file hỏng, runGuarded nhả lock kể cả khi action ném lỗi) · alarm_schedule_guard_test (throttle/force, justPassed biên grace, nextInstanceOf qua ngày/tháng) · analyze_rain_test (+rainEndsAt/duration + quan trắc/segments/nowcast-khô-vs-hourly + xác suất-không-ép-sàn-khi-sắp-mưa + 2-cơn-mưa-cường-độ) · weather_model_test (mapper thiếu trường→null, conditionId null, trích chi tiết 4.0) · uv_advice_test · build_weather_alerts_test (+nhắc lại/bất đối xứng/diễn biến) · weather_condition_test · build_rain_outlook_test · build_daily_digest_test · build_advisories_test · detect_env_change_test · digest_prefs_test (normalize/migrate/ánh xạ alarm ID) · note_local_datasource_test · note_notification_logic_test · announcement_repository_test (schema v3 + dedup seen + markSeen idempotent) · event_status_test (computeStatus còn hạn/hết hạn/sắp thi) · fixtures/fake_weather (kịch bản dữ liệu giả)
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
