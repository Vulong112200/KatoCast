import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/background/foreground_service.dart';
import '../../../../core/diagnostics/app_log.dart';
import '../../../../core/diagnostics/log_entry.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/widgets/app_error_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../providers/diagnostics_providers.dart';

/// Màn "Nhật ký hoạt động" — xem app đã làm gì, lúc nào, và vì sao có/không
/// thông báo.
///
/// Đây là công cụ chẩn đoán chính cho các lỗi chạy nền: trước đây toàn bộ đường
/// nền bọc `catch (_) {}` nên một chu kỳ thất bại không để lại dấu vết nào, không
/// thể biết app ngủ mất lúc nào hay vì sao một tin bị báo hai lần.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(filteredLogEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký hoạt động'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(ref),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'copy' => _copyAll(context, ref),
              'clear' => _confirmClear(context, ref),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Copy toàn bộ nhật ký'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Xoá nhật ký'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: entriesAsync.when(
          loading: () => const LoadingWidget(message: 'Đang đọc nhật ký...'),
          error: (e, _) => AppErrorWidget(error: e, onRetry: () => _refresh(ref)),
          data: (entries) => ListView(
            children: [
              const _HealthCard(),
              const _RuntimeCard(),
              const _FilterBar(),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Chưa có dòng nhật ký nào khớp.\n\nNhật ký được ghi mỗi khi '
                      'app chạy chu kỳ nền — hãy quay lại sau một chu kỳ, hoặc bỏ '
                      'bộ lọc.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ..._buildGroupedEntries(context, entries),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(logEntriesProvider);
    ref.invalidate(runtimeStatusProvider);
  }

  /// Gom theo ngày, mỗi ngày một tiêu đề rồi tới các dòng của ngày đó.
  List<Widget> _buildGroupedEntries(
    BuildContext context,
    List<LogEntry> entries,
  ) {
    final widgets = <Widget>[];
    String? currentDay;
    for (final entry in entries) {
      if (entry.dayKey != currentDay) {
        currentDay = entry.dayKey;
        widgets.add(_DayHeader(day: currentDay));
      }
      widgets.add(_LogTile(entry: entry));
    }
    return widgets;
  }

  Future<void> _copyAll(BuildContext context, WidgetRef ref) async {
    final text = await AppLog.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã copy nhật ký vào clipboard.')),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá nhật ký?'),
        content: const Text(
          'Toàn bộ dòng nhật ký sẽ bị xoá. Nếu đang truy một lỗi chạy nền, hãy '
          'copy lại trước khi xoá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppLog.clear();
    _refresh(ref);
  }
}

/// Thẻ "Tình trạng" — trả lời trực tiếp câu "app có đang chạy không".
class _HealthCard extends ConsumerWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(logHealthProvider);
    return healthAsync.maybeWhen(
      data: (h) => Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tình trạng', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _row(context, 'Chu kỳ gần nhất',
                  _agoLabel(h.lastCycleAt, suffix: h.lastCycleSource)),
              _row(context, 'Lấy dữ liệu OK gần nhất', _agoLabel(h.lastFetchOkAt)),
              _row(context, 'Thông báo gần nhất', _agoLabel(h.lastNotifyAt)),
              _row(context, 'Alarm kế tiếp', _atLabel(h.nextAlarmAt)),
              _row(
                context,
                'Khoảng ngủ dài nhất (24h)',
                h.longestGap24h == null ? '—' : _dur(h.longestGap24h!),
                // Ngủ quá 1 tiếng trong khung giờ hoạt động là dấu hiệu chuỗi đứt.
                warn: (h.longestGap24h?.inMinutes ?? 0) > 60,
              ),
              const Divider(height: 20),
              _row(
                context,
                '24h qua',
                '${h.cycles24h} chu kỳ · ${h.fetches24h} lần lấy dữ liệu · '
                    '${h.notifies24h} thông báo',
              ),
              _row(
                context,
                'Bỏ lượt do chống chạy chồng',
                '${h.lockSkips24h} lần',
              ),
              _row(
                context,
                'Lỗi 24h qua',
                '${h.errors24h} lỗi',
                warn: h.errors24h > 0,
              ),
              if (h.lastErrorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Lỗi gần nhất (${_agoLabel(h.lastErrorAt)}): '
                  '${h.lastErrorMessage}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Thẻ điều kiện thiết bị — những thứ quyết định chạy nền có sống được không.
class _RuntimeCard extends ConsumerWidget {
  const _RuntimeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(runtimeStatusProvider);
    return statusAsync.maybeWhen(
      data: (s) => Card(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cấu hình & quyền',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _check(context, 'Theo dõi liên tục',
                  s.foregroundEnabled ? s.foregroundRunning : null,
                  offLabel: s.foregroundEnabled
                      ? 'BỊ HỆ THỐNG DỪNG'
                          '${s.foregroundDeadFor == null ? '' : ' — ${_dur(s.foregroundDeadFor!)} trước'}'
                      : 'đã tắt trong Cài đặt',
                  onLabel: 'đang chạy'),
              // Chỉ app đang HIỂN THỊ mới được start foreground service (Android
              // 12+), nên đây là chỗ hợp pháp để bật lại bằng một lần chạm — và
              // là lý do trang này có nút thay vì để isolate nền tự xử lý.
              if (s.foregroundEnabled && !s.foregroundRunning)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Bật lại theo dõi liên tục'),
                    onPressed: () async {
                      final ok = await startWeatherForegroundService(
                          allowRestart: false);
                      ref.invalidate(runtimeStatusProvider);
                      ref.invalidate(logEntriesProvider);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Đã bật lại theo dõi liên tục 🐾'
                            : 'Chưa bật được — kiểm tra quyền vị trí ở dưới.'),
                      ));
                    },
                  ),
                ),
              _check(context, 'Quyền báo thức chính xác', s.exactAlarmGranted,
                  offLabel: 'chưa cấp — thông báo có thể lệch giờ'),
              _check(context, 'Pin không giới hạn', s.batteryUnrestricted,
                  offLabel: 'chưa bật — máy có thể giết app'),
              _check(context, 'Vị trí "Luôn cho phép"', s.backgroundLocation,
                  offLabel: 'CHƯA cấp — nền không tự cập nhật được vị trí, '
                      'thời tiết sẽ theo chỗ cũ khi bạn di chuyển'),
              if (!s.backgroundLocation)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Cấp quyền vị trí nền'),
                    onPressed: () async {
                      await ref
                          .read(permissionServiceProvider)
                          .requestBackgroundLocation();
                      ref.invalidate(runtimeStatusProvider);
                    },
                  ),
                ),
              _row(context, 'Chu kỳ nền', '${s.intervalMinutes} phút'),
              _row(
                context,
                'Khung giờ hoạt động',
                s.activeAllDay
                    ? 'cả ngày (24/7)'
                    : '${_hhmm(s.activeStartMinutes)}–${_hhmm(s.activeEndMinutes)}',
              ),
            ],
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(logFilterProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm trong nhật ký…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(logSearchProvider.notifier).state = v,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final f in LogFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: selected == f,
                    onSelected: (_) =>
                        ref.read(logFilterProvider.notifier).state = f,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String day;
  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(day, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// Một dòng nhật ký. Giờ + nguồn + nội dung; `data` hiện thành dòng phụ đơn sắc.
class _LogTile extends StatelessWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.level) {
      LogLevel.info => scheme.onSurfaceVariant,
      LogLevel.warn => Colors.orange,
      LogLevel.error => scheme.error,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              entry.hhmmss,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Icon(
              switch (entry.level) {
                LogLevel.info => Icons.circle,
                LogLevel.warn => Icons.warning_amber_rounded,
                LogLevel.error => Icons.error_outline,
              },
              size: entry.level == LogLevel.info ? 8 : 14,
              color: color,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${LogSource.label(entry.source)} · ',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: entry.message),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (entry.data.isNotEmpty)
                  Text(
                    entry.data.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('  ·  '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontSize: 11,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- helper dùng chung cho các thẻ ---

Widget _row(BuildContext context, String label, String value,
    {bool warn = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          flex: 5,
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: warn ? Theme.of(context).colorScheme.error : null,
                ),
          ),
        ),
      ],
    ),
  );
}

/// Dòng có dấu ✓/✕. [value] null = trạng thái "bật nhưng không chạy" (cảnh báo).
Widget _check(
  BuildContext context,
  String label,
  bool? value, {
  required String offLabel,
  String onLabel = 'OK',
}) {
  final ok = value == true;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: ok ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: ${ok ? onLabel : offLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

String _agoLabel(DateTime? at, {String? suffix}) {
  if (at == null) return '—';
  final ago = DateTime.now().difference(at);
  final label = '${_hhmmss(at)} (${_dur(ago)} trước)';
  return suffix == null ? label : '$label · ${LogSource.label(suffix)}';
}

String _atLabel(DateTime? at) {
  if (at == null) return '—';
  final now = DateTime.now();
  if (at.isBefore(now)) {
    return '${_hhmmss(at)} — ĐÃ QUÁ HẠN ${_dur(now.difference(at))}';
  }
  return '${_hhmmss(at)} (sau ${_dur(at.difference(now))})';
}

String _dur(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes} phút';
  return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

String _hhmmss(DateTime dt) {
  final t = dt.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

String _hhmm(int minutesOfDay) {
  final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minutesOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
