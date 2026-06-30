import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../alerts/domain/usecases/build_daily_digest.dart';
import '../../alerts/presentation/providers/notification_settings_provider.dart';
import '../../weather/presentation/providers/weather_provider.dart';

/// Màn hình cài đặt: giao diện (theme), thông báo, chạy nền & pin, giới thiệu.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          _sectionTitle(context, 'Giao diện'),

          // Chế độ sáng/tối/hệ thống.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Sáng'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Tối'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Hệ thống'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged: (s) => controller.setMode(s.first),
            ),
          ),

          // Bảng màu chọn sẵn — mờ đi khi đang dùng dynamic/weather.
          ListTile(
            title: const Text('Bảng màu'),
            subtitle: Text(
              settings.weatherAdaptive
                  ? 'Đang đổi màu theo thời tiết'
                  : settings.useDynamicColor
                      ? 'Đang dùng màu hệ thống (Material You)'
                      : 'Chọn tông màu chủ đạo',
            ),
          ),
          Opacity(
            opacity:
                (settings.weatherAdaptive || settings.useDynamicColor) ? 0.4 : 1,
            child: IgnorePointer(
              ignoring: settings.weatherAdaptive || settings.useDynamicColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final p in kAppPalettes)
                      _PaletteDot(
                        palette: p,
                        selected: settings.paletteId == p.id,
                        onTap: () => controller.setPalette(p.id),
                      ),
                  ],
                ),
              ),
            ),
          ),

          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('Material You'),
            subtitle: const Text('Tự lấy màu theo hình nền (Android 12+)'),
            value: settings.useDynamicColor,
            onChanged: (v) => controller.setUseDynamicColor(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_cloudy_outlined),
            title: const Text('Đổi màu theo thời tiết'),
            subtitle: const Text('Giao diện tự đổi tông theo tình hình hiện tại'),
            value: settings.weatherAdaptive,
            onChanged: (v) => controller.setWeatherAdaptive(v),
          ),

          const Divider(height: 32),
          _sectionTitle(context, 'Thông báo'),
          _NotificationTile(),
          const _DailyDigestSettings(),

          const Divider(height: 32),
          _sectionTitle(context, 'Chạy nền & pin'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'KatoCast kiểm tra thời tiết định kỳ kể cả khi bạn đã tắt app. '
              'Một số hãng (Xiaomi/MIUI, Samsung, Oppo…) có thể chặn tiến trình '
              'nền, khiến thông báo bị trễ hoặc mất. Hãy cho phép app chạy nền '
              'và bỏ giới hạn pin để thông báo hoạt động ổn định.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Bỏ giới hạn pin cho KatoCast'),
            subtitle: const Text('Mở hộp thoại whitelist tối ưu hóa pin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ok = await ref
                  .read(permissionServiceProvider)
                  .requestIgnoreBatteryOptimizations();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Đã bỏ giới hạn pin cho KatoCast.'
                        : 'Chưa bật. Bạn có thể chỉnh trong Cài đặt > Pin.'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_applications_outlined),
            title: const Text('Mở cài đặt ứng dụng'),
            subtitle: const Text(
                'Xiaomi: bật "Tự khởi động" & "Không giới hạn" trong mục Pin; '
                'Samsung: tắt "Đưa app vào chế độ ngủ".'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(permissionServiceProvider).openSettings(),
          ),

          const Divider(height: 32),
          _sectionTitle(context, 'Giới thiệu'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('KatoCast'),
            subtitle: Text('Dự báo thời tiết cá nhân hóa · phiên bản 1.0.0'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      );
}

/// Chấm màu chọn bảng màu.
class _PaletteDot extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteDot({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.seed,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(height: 4),
          Text(palette.label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Ô trạng thái quyền thông báo + nút bật / mở cài đặt.
class _NotificationTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final granted =
        await ref.read(permissionServiceProvider).isNotificationGranted();
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    return ListTile(
      leading: Icon(
        granted == true
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      title: const Text('Thông báo thời tiết'),
      subtitle: Text(
        granted == null
            ? 'Đang kiểm tra…'
            : granted
                ? 'Đã bật — bạn sẽ nhận cảnh báo mưa và thay đổi thời tiết.'
                : 'Đang tắt — bật để nhận cảnh báo chủ động.',
      ),
      trailing: granted == false
          ? TextButton(
              onPressed: () async {
                final ok = await ref
                    .read(permissionServiceProvider)
                    .requestNotificationPermission();
                if (!ok) {
                  await ref.read(permissionServiceProvider).openSettings();
                }
                await _refresh();
              },
              child: const Text('Bật'),
            )
          : null,
    );
  }
}

/// Cài đặt "Bản tin hằng ngày": bật/tắt + chỉnh giờ sáng/chiều + gửi thử.
class _DailyDigestSettings extends ConsumerWidget {
  const _DailyDigestSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationSettingsProvider);
    final controller = ref.read(notificationSettingsProvider.notifier);
    final enabled = prefs.enabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.schedule_outlined),
          title: const Text('Bản tin hằng ngày'),
          subtitle: const Text(
            'Tự gửi tóm tắt nhiệt độ, tình hình và lưu ý vào khung giờ bạn chọn.',
          ),
          value: enabled,
          onChanged: (v) => controller.setEnabled(v),
        ),
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TimeTile(
                  icon: Icons.wb_twilight_outlined,
                  label: 'Buổi sáng',
                  minutes: prefs.morningMinutes,
                  onPick: controller.setMorning,
                ),
                _TimeTile(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Buổi chiều',
                  minutes: prefs.eveningMinutes,
                  onPick: controller.setEvening,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Gửi thử bản tin ngay'),
              onPressed: () => _sendTest(context, ref),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendTest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref.read(weatherProvider.future);
      final digest = const BuildDailyDigest().call(data);
      final notif = NotificationService();
      await notif.show(
        id: NotificationIds.dailyDigestMorning,
        title: digest.title,
        body: digest.body,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã gửi bản tin thử.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Chưa lấy được dữ liệu thời tiết để gửi thử.'),
        ),
      );
    }
  }
}

/// Một dòng chọn giờ (mở time picker) cho bản tin.
class _TimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int minutes;
  final Future<void> Function(TimeOfDay) onPick;

  const _TimeTile({
    required this.icon,
    required this.label,
    required this.minutes,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final time = minutesToTimeOfDay(minutes);
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        time.format(context),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) await onPick(picked);
      },
    );
  }
}
