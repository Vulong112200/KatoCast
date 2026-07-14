import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'core/app_router.dart';
import 'core/background/background_triggers.dart';
import 'core/background/weather_check.dart';
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
    // Xin quyền báo thức CHÍNH XÁC (Android 12/API 31): thiếu quyền → bản tin
    // hẹn giờ chỉ nổ gần đúng. Vô hại trên Android 13+ (USE_EXACT_ALARM tự cấp).
    try {
      await ref.read(permissionServiceProvider).requestExactAlarmPermission();
    } catch (_) {}

    // 2. Đăng ký lớp chạy nền. `applyBackgroundTriggers` đảm bảo CHỈ MỘT cơ chế
    //    drive `runWeatherCheck` tại một thời điểm (tránh 3 lớp cùng đánh thức
    //    máy mỗi chu kỳ gây nóng): foreground service khi bật, hoặc alarm exact
    //    + WorkManager khi tắt. Xem `background_triggers.dart`.
    await applyBackgroundTriggers();

    // 2b. Xin bỏ giới hạn pin (whitelist) để nền chạy ổn định trên các máy diệt
    //     tiến trình mạnh (Xiaomi/HyperOS, Oppo…). Nhắc lại theo chu kỳ nếu chưa
    //     được cấp (không phải chỉ một lần) vì đây là điều kiện then chốt để cả
    //     foreground service lẫn alarm sống sót.
    await _promptBatteryIfNeeded();

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

    // 4b. Chạy kiểm tra thời tiết NGAY khi mở app (một lần) → khởi tạo trạng
    //     thái cảnh báo (AlertStateStore) + bắn cảnh báo tức thì nếu đang
    //     sắp/đổi mưa + làm tươi thông báo thường trực. Không await để không
    //     chặn khởi động UI; bọc catch vì runWeatherCheck tự dựng/đóng DB.
    runWeatherCheck().catchError((_) => null);

    // 4c. Onboarding chống bị OEM giết (Nubia/MyOS…): lần đầu, nếu chưa bỏ giới
    //     hạn pin → hướng dẫn bật Tự khởi động + Không giới hạn pin.
    await _promptAutostartOnboardingIfNeeded();

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
