import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'core/app_router.dart';
import 'core/background/background_worker.dart';
import 'core/di/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/theme_palettes.dart';
import 'core/theme/weather_theme.dart';
import 'features/alerts/data/digest_scheduler.dart';
import 'features/alerts/data/notification_prefs_store.dart';
import 'features/location/presentation/providers/location_provider.dart';
import 'features/notes/data/note_notification_service.dart';
import 'features/notes/presentation/providers/notes_provider.dart';
import 'features/weather/presentation/providers/weather_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo timezone cho thông báo (lập lịch theo local time).
  tz.initializeTimeZones();
  // Set múi giờ địa phương — nếu thiếu, tz.local mặc định UTC khiến
  // zonedSchedule bắn sai giờ (vd 6:30 local thành 6:30 UTC = 13:30 VN).
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));
  } catch (_) {
    // Không lấy được tên múi giờ → giữ mặc định, app vẫn chạy.
  }

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
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // 1. Khởi tạo channel thông báo + xin quyền (Android 13+). Từ chối → app
    //    vẫn chạy, chỉ không gửi alert.
    await ref.read(notificationServiceProvider).init();
    await ref.read(permissionServiceProvider).requestNotificationPermission();

    // 2. Đăng ký background check định kỳ. Bọc try để app không chết nếu
    //    WorkManager lỗi trên một số máy.
    try {
      await BackgroundScheduler.initialize();
    } catch (_) {}

    // 2b. Lần đầu chạy: xin bỏ giới hạn pin (whitelist) để nền chạy ổn định
    //     trên các máy diệt tiến trình mạnh (Xiaomi/HyperOS, Oppo…). Chỉ hỏi
    //     một lần để không làm phiền; sau đó người dùng tự chỉnh trong Settings.
    await _promptBatteryOnce();

    // 3. Lập lịch bản tin hằng ngày qua alarm hệ thống (đáng tin hơn
    //    WorkManager). Nội dung lấy từ cache mới nhất; mỗi lần worker chạy /
    //    đổi cài đặt sẽ lập lịch lại để nội dung tươi nhất có thể.
    await _rescheduleDigests();

    // 4. Ghi chú: hiện lại notification ghim (mất sau reboot / "Xoá tất cả"
    //    trên Android 14) + lập lại lịch nhắc theo trạng thái DB — đồng bộ cả
    //    khi "Đã đọc" được bấm lúc app tắt.
    try {
      await reassertNoteNotifications(
        ref.read(appDatabaseProvider),
        ref.read(notificationServiceProvider),
      );
    } catch (_) {}

    // 5. App được mở từ notification ghi chú (cold launch) → vào màn Ghi chú.
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

  Future<void> _promptBatteryOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'battery_prompt_shown';
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
      await ref.read(permissionServiceProvider).requestIgnoreBatteryOptimizations();
    } catch (_) {}
  }

  Future<void> _rescheduleDigests() async {
    try {
      // Chỉ cần lập lịch alarm đúng mốc giờ theo cài đặt; nội dung sẽ được
      // callback tự fetch tươi lúc bắn nên KHÔNG cần đợi weatherProvider ở đây.
      final prefs = await NotificationPrefsStore().read();
      await scheduleDigests(prefs);
    } catch (_) {
      // Lỗi lập lịch (vd nền tảng không hỗ trợ AlarmManager) → bỏ qua.
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
          title: 'KatoCast',
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
