import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../alerts/data/digest_scheduler.dart';
import '../../../alerts/domain/usecases/build_daily_digest.dart';
import '../../../alerts/presentation/providers/notification_settings_provider.dart';
import '../providers/weather_provider.dart';

/// Thẻ cài đặt "Bản tin hằng ngày" trong màn Thời tiết: bật/tắt + danh sách
/// nhiều mốc giờ (thêm/xóa tùy ý) + cảnh báo quyền báo thức chính xác + gửi thử.
///
/// Thay cho phần cũ ở màn Settings (chỉ có 2 mốc cố định sáng/chiều).
class DigestSettingsCard extends ConsumerStatefulWidget {
  const DigestSettingsCard({super.key});

  @override
  ConsumerState<DigestSettingsCard> createState() => _DigestSettingsCardState();
}

class _DigestSettingsCardState extends ConsumerState<DigestSettingsCard> {
  /// null = đang kiểm tra; true/false = kết quả quyền exact-alarm.
  bool? _exactGranted;

  @override
  void initState() {
    super.initState();
    _refreshExact();
  }

  Future<void> _refreshExact() async {
    final granted =
        await ref.read(permissionServiceProvider).isExactAlarmGranted();
    if (mounted) setState(() => _exactGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationSettingsProvider);
    final controller = ref.read(notificationSettingsProvider.notifier);
    final enabled = prefs.enabled;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.schedule_outlined),
            title: const Text('Bản tin hằng ngày'),
            subtitle: const Text(
              'Tự gửi tóm tắt nhiệt độ, tình hình và lưu ý vào các mốc giờ bạn '
              'đặt bên dưới.',
            ),
            value: enabled,
            onChanged: (v) => controller.setEnabled(v),
          ),
          if (enabled && _exactGranted == false)
            _ExactAlarmWarning(onRequest: () async {
              await ref
                  .read(permissionServiceProvider)
                  .requestExactAlarmPermission();
              await _refreshExact();
            }),
          Opacity(
            opacity: enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (prefs.times.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Chưa có mốc giờ nào. Bấm "Thêm mốc giờ".'),
                      ),
                    ),
                  for (var i = 0; i < prefs.times.length; i++)
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(
                        minutesToTimeOfDay(prefs.times[i]).format(context),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: IconButton(
                        tooltip: 'Xóa mốc',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.removeTime(i),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: minutesToTimeOfDay(prefs.times[i]),
                        );
                        if (picked != null) controller.updateTime(i, picked);
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm mốc giờ'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) controller.addTime(picked);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton.icon(
                icon: const Icon(Icons.send_outlined),
                label: const Text('Gửi thử bản tin ngay'),
                onPressed: () => _sendTest(context, ref),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: TextButton.icon(
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Đặt bản tin thử sau 1 phút (test chạy nền)'),
                onPressed: () => _sendScheduledTest(context),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Mẹo chẩn đoán: bấm nút trên rồi KHÓA màn hình ~1 phút — nếu nổ là '
              'lập lịch chạy nền OK. Nếu bạn VUỐT TẮT app rồi không nổ → hãy bật '
              '"Tự khởi động" + đặt pin "Không giới hạn" trong Cài đặt.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendScheduledTest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await scheduleDigestTest();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Đã đặt bản tin thử sau 1 phút. Khóa màn hình và chờ.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không đặt được lịch thử trên máy này.')),
      );
    }
  }

  Future<void> _sendTest(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref.read(weatherProvider.future);
      final digest = const BuildDailyDigest().call(data);
      final notif = NotificationService();
      await notif.show(
        id: NotificationIds.digestBase,
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

/// Dòng cảnh báo khi thiếu quyền báo thức chính xác — bản tin có thể lệch giờ.
class _ExactAlarmWarning extends StatelessWidget {
  final VoidCallback onRequest;
  const _ExactAlarmWarning({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Để bản tin nổ ĐÚNG giờ, hãy cấp quyền "Báo thức & lời nhắc" '
            '(báo thức chính xác). Thiếu quyền, bản tin vẫn nổ nhưng có thể '
            'lệch giờ.',
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRequest,
              child: const Text('Cấp quyền'),
            ),
          ),
        ],
      ),
    );
  }
}
