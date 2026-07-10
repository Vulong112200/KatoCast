import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../alerts/presentation/providers/notification_settings_provider.dart'
    show minutesToTimeOfDay;
import 'providers/background_settings_provider.dart';

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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Cài đặt "Bản tin hằng ngày" (thêm/bớt mốc giờ) đã chuyển sang màn '
              'Thời tiết, ngay dưới dự báo theo giờ.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),

          const Divider(height: 32),
          _sectionTitle(context, 'Chạy nền & pin'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'KatoAssistant kiểm tra thời tiết định kỳ kể cả khi bạn đã tắt app. '
              'Nhiều hãng (Nubia/MyOS, Xiaomi/HyperOS, Oppo, vivo…) khi bạn VUỐT '
              'TẮT app khỏi màn hình gần đây sẽ dừng app và HỦY mọi thông báo hẹn '
              'giờ. Để thông báo hoạt động ổn định, hãy BẬT "Tự khởi động" và đặt '
              'pin ở chế độ "Không giới hạn" cho KatoAssistant.',
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('Theo dõi thời tiết liên tục'),
            subtitle: const Text(
              'Giữ một thông báo thường trực để cập nhật thời tiết & cảnh báo '
              'mưa đều đặn kể cả khi tắt màn hình. Tắt nếu bạn không muốn thông '
              'báo thường trực (thông báo có thể kém kịp thời hơn).',
            ),
            value: ref.watch(backgroundSettingsProvider).foregroundEnabled,
            onChanged: (v) => ref
                .read(backgroundSettingsProvider.notifier)
                .setForegroundEnabled(v),
          ),
          const _IntervalSetting(),
          const _ActiveHoursSetting(),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Bỏ giới hạn pin cho KatoAssistant'),
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
                        ? 'Đã bỏ giới hạn pin cho KatoAssistant.'
                        : 'Chưa bật. Bạn có thể chỉnh trong Cài đặt > Pin.'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('Bật "Tự khởi động" (Autostart)'),
            subtitle: const Text(
                'Cho phép KatoAssistant tự chạy lại — BẮT BUỘC để thông báo nổ đúng '
                'giờ sau khi vuốt tắt app (Nubia/Xiaomi/Oppo…).'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                ref.read(permissionServiceProvider).openAutoStartSettings(),
          ),
          ListTile(
            leading: const Icon(Icons.settings_applications_outlined),
            title: const Text('Mở cài đặt ứng dụng'),
            subtitle: const Text(
                'Nếu không mở được trang Tự khởi động: vào đây → mục Pin đặt '
                '"Không giới hạn"; Nubia/MyOS: bật "Tự khởi động" trong quản lý '
                'ứng dụng nền.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(permissionServiceProvider).openSettings(),
          ),

          const Divider(height: 32),
          _sectionTitle(context, 'Giới thiệu'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('KatoAssistant'),
            subtitle:
                Text('Trợ lý cá nhân: thời tiết & thông báo · phiên bản 1.0.0'),
          ),
          ListTile(
            leading: const Text('🐱', style: TextStyle(fontSize: 24)),
            title: const Text('Về chú mèo Kato'),
            subtitle: const Text('Vì sao app tên là KatoAssistant?'),
            onTap: () => _showAboutKato(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showAboutKato(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🐱 Chú mèo Kato'),
        content: const Text(
          'KatoAssistant được đặt theo tên Kato — chú mèo Bengal lai mèo rừng ta, '
          'lông nâu sọc trắng. Kato thính tai, nhạy mũi và rất giỏi "đánh hơi" — '
          'không chỉ thời tiết mà cả những tin bạn đang ngóng (lịch thi, khoá '
          'học…). Cậu ấy tha tin về cho bạn mỗi ngày. 🐾',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Meo~ đóng lại'),
          ),
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

/// Bộ chọn chu kỳ cập nhật nền (5/10/15/30') + cảnh báo hạn mức/pin.
class _IntervalSetting extends ConsumerWidget {
  const _IntervalSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(backgroundSettingsProvider).intervalMinutes;
    final controller = ref.read(backgroundSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Chu kỳ cập nhật nền'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SegmentedButton<int>(
            segments: [
              for (final m in AppConfig.backgroundIntervalOptions)
                ButtonSegment(value: m, label: Text("$m'")),
            ],
            selected: {current},
            onSelectionChanged: (s) => controller.setIntervalMinutes(s.first),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Chu kỳ ngắn (5–10\') cập nhật kịp thời hơn nhưng tốn pin/làm nóng '
            'máy hơn và tiêu hạn mức API nhanh (mỗi lần làm mới = 3 lượt gọi; '
            '5\' ≈ 860 lượt/ngày, gần trần 1000/ngày). Khi tắt "Theo dõi liên '
            'tục", hệ thống cập nhật tối thiểu mỗi 15\'.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Khung giờ hoạt động: cả ngày (24/7) hoặc giới hạn giờ bắt đầu→kết thúc.
/// Ngoài khung, app tạm ngủ (không lấy dữ liệu) để tiết kiệm pin/hạn mức API;
/// alarm backstop tự thức lại đúng giờ mở khung. Bản tin hằng ngày KHÔNG bị
/// chặn — vẫn nổ đúng mốc đã đặt.
class _ActiveHoursSetting extends ConsumerWidget {
  const _ActiveHoursSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(backgroundSettingsProvider);
    final controller = ref.read(backgroundSettingsProvider.notifier);

    Future<void> pick(int currentMinutes, ValueChanged<int> onPicked) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: minutesToTimeOfDay(currentMinutes),
      );
      if (picked != null) onPicked(picked.hour * 60 + picked.minute);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.schedule_outlined),
          title: const Text('Hoạt động cả ngày (24/7)'),
          subtitle: const Text(
            'Bật: theo dõi suốt ngày đêm. Tắt: chỉ hoạt động trong khung giờ '
            'bên dưới — ngoài khung app tạm ngủ để mát máy & tiết kiệm hạn mức, '
            'tự thức lại vào giờ bắt đầu.',
          ),
          value: s.activeAllDay,
          onChanged: controller.setActiveAllDay,
        ),
        Opacity(
          opacity: s.activeAllDay ? 0.4 : 1.0,
          child: IgnorePointer(
            ignoring: s.activeAllDay,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.wb_twilight_outlined),
                  title: const Text('Bắt đầu'),
                  trailing: Text(
                    minutesToTimeOfDay(s.activeStartMinutes).format(context),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => pick(
                      s.activeStartMinutes, controller.setActiveStartMinutes),
                ),
                ListTile(
                  leading: const Icon(Icons.nightlight_outlined),
                  title: const Text('Kết thúc'),
                  trailing: Text(
                    minutesToTimeOfDay(s.activeEndMinutes).format(context),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () =>
                      pick(s.activeEndMinutes, controller.setActiveEndMinutes),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Bản tin hằng ngày vẫn nổ đúng giờ bạn đặt, kể cả ngoài khung này.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
