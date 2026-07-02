import 'package:go_router/go_router.dart';

import '../features/fixed_route/presentation/screens/route_screen.dart';
import '../features/map_news/presentation/screens/map_screen.dart';
import '../features/notes/presentation/screens/note_edit_screen.dart';
import '../features/notes/presentation/screens/notes_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/weather/presentation/screens/weather_screen.dart';

/// GoRouter — màn thời tiết + cài đặt. Cấu trúc để Phase 2 thêm route
/// (bản đồ/tin tức, lộ trình cố định) dễ dàng.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'weather',
      builder: (context, state) => const WeatherScreen(),
    ),
    GoRoute(
      path: '/map',
      name: 'map',
      builder: (context, state) => const MapScreen(),
    ),
    GoRoute(
      path: '/routes',
      name: 'routes',
      builder: (context, state) => const RouteScreen(),
    ),
    GoRoute(
      path: '/notes',
      name: 'notes',
      builder: (context, state) => const NotesScreen(),
    ),
    GoRoute(
      path: '/notes/edit',
      name: 'noteEdit',
      builder: (context, state) =>
          NoteEditScreen(noteId: state.extra as int?),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
