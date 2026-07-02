import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Drawer điều hướng chính giữa các màn của app.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = GoRouterState.of(context).matchedLocation;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: scheme.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.cloud, size: 40, color: scheme.onPrimaryContainer),
                const SizedBox(height: 8),
                Text('KatoCast',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        )),
                Text('Dự báo thời tiết cá nhân hóa',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        )),
              ],
            ),
          ),
          _item(context, current, '/', Icons.wb_sunny_outlined, 'Thời tiết'),
          _item(context, current, '/map', Icons.map_outlined,
              'Bản đồ & Tin tức'),
          _item(context, current, '/routes', Icons.alt_route,
              'Lộ trình & tiện ích'),
          _item(context, current, '/notes', Icons.sticky_note_2_outlined,
              'Ghi chú'),
          const Divider(),
          _item(context, current, '/settings', Icons.settings_outlined,
              'Cài đặt'),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String current,
    String path,
    IconData icon,
    String label,
  ) {
    final selected = current == path;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.of(context).pop(); // đóng drawer
        if (!selected) {
          path == '/' ? context.go(path) : context.push(path);
        }
      },
    );
  }
}
