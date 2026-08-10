import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_router.dart';
import 'core/background/background_prefs.dart';
import 'core/background/background_triggers.dart';
import 'core/background/cycle_lock.dart';
import 'core/background/foreground_service.dart';
import 'core/background/service_health.dart';
import 'core/background/weather_check.dart';
import 'core/diagnostics/app_log.dart';
import 'core/diagnostics/log_entry.dart';
import 'core/diagnostics/log_tags.dart';
import 'core/di/providers.dart';
import 'core/notifications/timezone_init.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/theme_palettes.dart';
import 'core/theme/weather_theme.dart';
import 'features/alerts/data/digest_scheduler.dart';
import 'features/alerts/data/notification_prefs_store.dart';
import 'features/announcements/data/announcement_prefs_store.dart';
import 'features/announcements/data/announcement_scheduler.dart';
import 'features/location/presentation/providers/location_provider.dart';
import 'features/notes/data/note_notification_service.dart';
import 'features/notes/presentation/providers/notes_provider.dart';
import 'features/weather/presentation/providers/weather_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo timezone cho thông báo (lập lịch theo local time). Nếu thiếu,
  // tz.local mặc định UTC khiến zonedSchedule bắn sai giờ (vd 6:30 local thành
  // 6:30 UTC = 13:30 VN). Hàm này cũng LƯU tên múi giờ vào SharedPreferences để
  // các isolate nền dùng lại — xem `timezone_init.dart`.
  await ensureTimezoneInitialized();

  // Khởi tạo AlarmManager để chạy callback nền cho bản tin hằng ngày đúng mốc
  // giờ (kể cả app đã tắt). Bọc try để app không chết nếu plugin lỗi/không hỗ
  // trợ nền tảng (vd iOS) — bản tin khi đó sẽ chỉ lập lịch được khi mở app.
  try {
    await AndroidAlarmManager.initialize();
  } catch (_) {}

  runApp(const ProviderScope(child: KatoCastApp()));
}

class KatoCastApp extends ConsumerStatefulWidget {
  const KatoCastApp({super.key});

  @override
  ConsumerState<KatoCastApp> createState() => _KatoCastAppState();
}

class _KatoCastAppState extends ConsumerState<KatoCastApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Sau frame đầu: init notification, xin quyền, đăng ký background task.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());

    // Mở/quay lại app → làm mới thời tiết (nhờ stale-while-revalidate ở
    // weatherProvider, cache còn tươi sẽ tự bỏ qua việc gọi API).
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.invalidate(weatherProvider);
        ref.invalidate(currentPlaceProvider);
        // Ghi chú: nút "Đã đọc" chạy ở isolate riêng ghi thẳng DB — main
        // isolate không tự thấy → nạp lại khi quay về app.
        ref.invalidate(notesControllerProvider);
        // App đang hiển thị = THỜI ĐIỂM DUY NHẤT được Android 12+ cho phép bật
        // lại foreground service. Đây là đường hồi phục chính sau khi hệ thống
        // dừng service (Android 15+ cắt FGS sau hạn mức thời lượng, hoặc OEM
        // giết tiến trình). Trước đây việc bật lại chỉ xảy ra ở cold start, nên
        // vào lại app từ nền thì service vẫn chết im.
        unawaited(_reviveForegroundServiceOnResume());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Chuỗi khởi động. **THỨ TỰ Ở ĐÂY LÀ CÓ CHỦ Ý** — xem từng mốc bên dưới.
  ///
  /// ⚠️ Bản trước xin quyền theo thứ tự "thông báo → báo thức chính xác → pin"
  /// rồi mới `applyBackgroundTriggers`, trong khi quyền VỊ TRÍ do
  /// `currentLocationProvider` tự xin từ frame đầu. Hai lỗi thật sinh ra từ đó:
  ///
  /// 1. **App đứng đơ màn hình trắng khi CÀI MỚI.** Hai lời xin quyền chạy song
  ///    song (permission_handler xin thông báo, geolocator xin vị trí); Android
  ///    thả im lặng lời gọi thứ hai nên future của nó treo vĩnh viễn →
  ///    `currentLocationProvider` không bao giờ xong → `WeatherScreen` xoay mãi,
  ///    và hộp thoại quyền vị trí KHÔNG hiện. Vuốt tắt rồi mở lại thì quyền
  ///    thông báo đã có nên không còn tranh chấp — đúng triệu chứng người dùng
  ///    báo. Nay mọi lời xin quyền xếp hàng qua `PermissionGate`, và mốc (1)
  ///    đăng ký vào hàng đợi TRƯỚC nên thứ tự hộp thoại là xác định.
  /// 2. **Lần chạy đầu không bật được "theo dõi liên tục".** Foreground service
  ///    khai báo `foregroundServiceType="location"` nên
  ///    `startWeatherForegroundService` từ chối start khi chưa có quyền vị trí
  ///    (start mà thiếu quyền = SecurityException = sập app). Bản cũ gọi
  ///    `applyBackgroundTriggers` TRƯỚC khi người dùng cấp quyền vị trí → lần
  ///    đầu luôn ghi "CHƯA bật theo dõi liên tục: thiếu quyền vị trí". Nay xin
  ///    quyền vị trí xong mới đăng ký các lớp nền.
  Future<void> _bootstrap() async {
    // 0. Ghi dấu mở app vào nhật ký — mốc để đọc trang "Nhật ký hoạt động" biết
    //    ranh giới giữa các phiên (và biết app có được mở lại giữa đường không).
    unawaited(AppLog.i(LogSource.ui, LogTags.boot, 'mở app'));

    // 1. Xin quyền THÔNG BÁO (Android 13+). Từ chối → app vẫn chạy, chỉ không
    //    gửi alert. Gọi TRƯỚC `notif.init()` và KHÔNG await ngay: hàm này đăng
    //    ký vào `PermissionGate` một cách đồng bộ, nên nó chiếm chỗ đầu hàng đợi
    //    trước lượt xin quyền vị trí (do frame đầu của WeatherScreen kích hoạt,
    //    lượt đó còn phải chờ 2 lời gọi platform trước khi vào hàng đợi).
    //    Bọc try: một lỗi ở khâu thông báo KHÔNG được làm đứt cả chuỗi khởi động
    //    phía sau (quyền vị trí, các lớp nền, bản tin) — trước đây hai lời gọi
    //    này không có lưới nào.
    try {
      final notificationPermission =
          ref.read(permissionServiceProvider).requestNotificationPermission();
      await ref.read(notificationServiceProvider).init();
      await notificationPermission;
    } catch (e, st) {
      await AppLog.e(LogSource.ui, LogTags.notify,
          'lỗi khởi tạo/xin quyền thông báo lúc mở app',
          error: e, stack: st);
    }

    // 2. App được mở từ notification ghi chú (cold launch) → vào màn Ghi chú.
    //    Làm sớm: điều hướng không nên phải đợi hết chuỗi hộp thoại quyền.
    await _routeFromLaunchNotification();

    // 3. Xin quyền VỊ TRÍ — quyền CỐT LÕI của app. Chờ xong ở đây để mốc (4)
    //    bật được foreground service kiểu `location` ngay trong lần chạy đầu.
    //    Người dùng từ chối cũng không sao: WeatherScreen tự hiện hướng dẫn.
    try {
      await ref.read(permissionServiceProvider).ensureLocationPermission();
    } catch (e) {
      await AppLog.w(
        LogSource.ui,
        LogTags.boot,
        'chưa có quyền vị trí lúc khởi động',
        data: {'lý do': e.toString()},
      );
    }

    // 4. Đăng ký các lớp chạy nền. `CycleLock` đảm bảo chỉ MỘT chu kỳ thực sự
    //    chạy tại một thời điểm, nên nhiều lớp cùng bật là nhiều đường hồi phục
    //    độc lập chứ không phải nguồn tranh chấp. Xem `background_triggers.dart`.
    await applyBackgroundTriggers();

    // 5. Lập lịch bản tin hằng ngày + hồi phục ghim/lịch ghi chú.
    //    KHÔNG await nối tiếp: cả hai đều thực hiện nhiều lời gọi binder
    //    AlarmManager/notification — chạy fire-and-forget để không giữ luồng
    //    chính (tránh ANR "App không hoạt động"); thứ tự với nhau không quan
    //    trọng vì mỗi hàm tự dựng dependency riêng.
    unawaited(_rescheduleDigests());
    unawaited(_rescheduleAnnouncementCheck());
    unawaited(() async {
      try {
        await reassertNoteNotifications(
          ref.read(appDatabaseProvider),
          ref.read(notificationServiceProvider),
        );
      } catch (e, st) {
        await AppLog.e(LogSource.ui, LogTags.db, 'lỗi re-assert ghim ghi chú',
            error: e, stack: st);
      }
    }());

    // 6. Chạy kiểm tra thời tiết NGAY khi mở app (một lần) → khởi tạo trạng
    //    thái cảnh báo (AlertStateStore) + bắn cảnh báo tức thì nếu đang
    //    sắp/đổi mưa + làm tươi thông báo thường trực. Không await để không
    //    chặn khởi động UI. Qua cycle lock để không đua với tick nền.
    unawaited(
      CycleLock.runGuarded(
        LogSource.ui,
        () => runWeatherCheck(source: LogSource.ui),
      ).catchError((_) => null),
    );

    // 7. Xin quyền báo thức CHÍNH XÁC (Android 12/API 31): thiếu quyền → bản
    //    tin hẹn giờ chỉ nổ gần đúng. Đặt SAU các quyền cốt lõi vì trên Android
    //    12 lời xin này MỞ MỘT MÀN CÀI ĐẶT HỆ THỐNG (đưa người dùng ra khỏi
    //    app) — không thể để nó chen ngang lúc app còn chưa vẽ xong lần đầu.
    //    Trên Android 13+ đã tự cấp qua USE_EXACT_ALARM nên hàm chỉ kiểm tra.
    try {
      await ref.read(permissionServiceProvider).requestExactAlarmPermission();
    } catch (_) {}

    // 8. Xin bỏ giới hạn pin (whitelist) để nền chạy ổn định trên các máy diệt
    //    tiến trình mạnh (Xiaomi/HyperOS, Oppo…). Nhắc lại theo chu kỳ nếu chưa
    //    được cấp (không phải chỉ một lần) vì đây là điều kiện then chốt để cả
    //    foreground service lẫn alarm sống sót.
    await _promptBatteryIfNeeded();

    // 9. Onboarding chống bị OEM giết (Nubia/MyOS…): lần đầu, nếu chưa bỏ giới
    //    hạn pin → hướng dẫn bật Tự khởi động + Không giới hạn pin.
    await _promptAutostartOnboardingIfNeeded();
  }

  /// Mở màn Ghi chú nếu app được khởi động bằng cách chạm notification ghi chú.
  Future<void> _routeFromLaunchNotification() async {
    try {
      final launch =
          await ref.read(notificationServiceProvider).getLaunchDetails();
      final resp = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          parseNotePayload(resp?.payload) != null) {
        appRouter.push('/notes');
      }
    } catch (_) {}
  }

  /// Bật lại theo dõi liên tục khi người dùng quay vào app, NẾU nó đã bị hệ
  /// thống dừng. Rẻ và im lặng: service còn chạy thì chỉ là một lời gọi
  /// `isRunningService` rồi thoát — KHÔNG restart (restart sẽ reset pha lặp và
  /// làm FG tick trùng pha alarm).
  Future<void> _reviveForegroundServiceOnResume() async {
    try {
      if (!await BackgroundPrefsStore().foregroundEnabled()) return;
      if (await FlutterForegroundTask.isRunningService) {
        await ForegroundServiceHealth.markAlive();
        await ForegroundServiceHealth.clearNudgeNotification();
        return;
      }
      await AppLog.w(
        LogSource.ui,
        LogTags.service,
        'theo dõi liên tục đã bị hệ thống dừng → bật lại vì app đang mở',
      );
      await startWeatherForegroundService(allowRestart: false);
    } catch (e, st) {
      await AppLog.e(LogSource.ui, LogTags.service,
          'không bật lại được theo dõi liên tục khi mở app',
          error: e, stack: st);
    }
  }

  Future<void> _promptBatteryIfNeeded() async {
    try {
      final permission = ref.read(permissionServiceProvider);
      // Đã whitelist → không nhắc.
      if (await permission.isIgnoringBatteryOptimizations()) return;

      final prefs = await SharedPreferences.getInstance();
      const key = 'battery_prompt_last_ms';
      final lastMs = prefs.getInt(key) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Giãn cách tối thiểu 7 ngày giữa hai lần nhắc để không làm phiền.
      const minGapMs = 7 * 24 * 60 * 60 * 1000;
      if (lastMs != 0 && nowMs - lastMs < minGapMs) return;
      await prefs.setInt(key, nowMs);
      await permission.requestIgnoreBatteryOptimizations();
    } catch (_) {}
  }

  /// Onboarding MỘT LẦN: hướng dẫn bật Tự khởi động + Không giới hạn pin để
  /// thông báo sống sót khi vuốt tắt app trên OEM diệt tiến trình mạnh.
  Future<void> _promptAutostartOnboardingIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'onboarded_bg';
      if (prefs.getBool(key) ?? false) return;

      final permission = ref.read(permissionServiceProvider);
      // Đã bỏ giới hạn pin rồi → coi như đã cấu hình cơ bản, chỉ ghi cờ.
      if (await permission.isIgnoringBatteryOptimizations()) {
        await prefs.setBool(key, true);
        return;
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Để thông báo nổ đúng giờ'),
          content: const SingleChildScrollView(
            child: Text(
              'Trên một số máy (Nubia/MyOS, Xiaomi/HyperOS, Oppo…), khi bạn '
              'VUỐT TẮT app khỏi danh sách gần đây, hệ điều hành sẽ dừng app và '
              'HỦY mọi thông báo hẹn giờ (bản tin, nhắc ghi chú, cảnh báo mưa).\n\n'
              'CÁCH CHẮC CHẮN NHẤT: ĐỪNG vuốt tắt app, hoặc KHÓA app trong màn '
              'hình gần đây — mở recent apps, vuốt xuống / giữ thẻ KatoAssistant '
              'rồi chọn biểu tượng khóa 🔒. Khi đã khóa, thao tác "Xóa tất cả" sẽ '
              'không giết app nữa.\n\n'
              'Ngoài ra hãy bật thêm để app sống ổn định:\n'
              '1) "Tự khởi động" (Autostart) cho KatoAssistant.\n'
              '2) Đặt pin ở chế độ "Không giới hạn".',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Để sau'),
            ),
            TextButton(
              onPressed: () => permission.requestIgnoreBatteryOptimizations(),
              child: const Text('Bỏ giới hạn pin'),
            ),
            FilledButton(
              onPressed: () => permission.openAutoStartSettings(),
              child: const Text('Mở Tự khởi động'),
            ),
          ],
        ),
      );
      await prefs.setBool(key, true);
    } catch (_) {}
  }

  Future<void> _rescheduleDigests() async {
    try {
      // Chỉ cần lập lịch alarm đúng mốc giờ theo cài đặt; nội dung sẽ được
      // callback tự fetch tươi lúc bắn nên KHÔNG cần đợi weatherProvider ở đây.
      final prefs = await NotificationPrefsStore().read();
      await scheduleDigests(prefs, force: true, source: LogSource.ui);
    } catch (e, st) {
      await AppLog.e(LogSource.ui, LogTags.digest, 'lỗi lập lịch bản tin khi mở app',
          error: e, stack: st);
    }
  }

  /// Tự chữa lịch poll tin mới khi mở app (giống bản tin). Nếu chuỗi alarm bị đứt
  /// trong đêm thì mở app là một trong các đường dựng lại.
  Future<void> _rescheduleAnnouncementCheck() async {
    try {
      final prefs = await AnnouncementPrefsStore().read();
      await scheduleAnnouncementCheck(prefs, force: true, source: LogSource.ui);
    } catch (e, st) {
      await AppLog.e(
          LogSource.ui, LogTags.announce, 'lỗi lập lịch poll tin khi mở app',
          error: e, stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeControllerProvider);
    // Tình hình thời tiết hiện tại (cho chế độ "đổi màu theo thời tiết").
    final condition = ref.watch(weatherConditionProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Thứ tự ưu tiên seed: thời tiết > Material You (dynamic) > bảng màu.
        Color seed = seedForPaletteId(settings.paletteId);
        ColorScheme? lightScheme;
        ColorScheme? darkScheme;

        if (settings.weatherAdaptive && condition != null) {
          seed = seedForCategory(condition.category);
        } else if (settings.useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        }

        return MaterialApp.router(
          title: 'KatoAssistant',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            seed: seed,
            brightness: Brightness.light,
            dynamicScheme: lightScheme,
          ),
          darkTheme: buildAppTheme(
            seed: seed,
            brightness: Brightness.dark,
            dynamicScheme: darkScheme,
          ),
          themeMode: settings.mode,
          routerConfig: appRouter,
        );
      },
    );
  }
}
