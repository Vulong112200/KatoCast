import 'package:go_router/go_router.dart';

import '../features/weather/presentation/screens/weather_screen.dart';

/// GoRouter — hiện chỉ có màn thời tiết. Cấu trúc để Phase 2 thêm route
/// (bản đồ/tin tức, lộ trình cố định) dễ dàng.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'weather',
      builder: (context, state) => const WeatherScreen(),
    ),
  ],
);
