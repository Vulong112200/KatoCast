import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'core/app_router.dart';
import 'core/background/background_worker.dart';
import 'core/di/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo timezone cho thông báo (lập lịch theo local time).
  tz.initializeTimeZones();

  runApp(const ProviderScope(child: KatoCastApp()));
}

class KatoCastApp extends ConsumerStatefulWidget {
  const KatoCastApp({super.key});

  @override
  ConsumerState<KatoCastApp> createState() => _KatoCastAppState();
}

class _KatoCastAppState extends ConsumerState<KatoCastApp> {
  @override
  void initState() {
    super.initState();
    // Sau frame đầu: init notification, xin quyền, đăng ký background task.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'KatoCast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
