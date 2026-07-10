import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/background/announcement_alarm.dart';
import '../../data/announcement_prefs_store.dart';
import '../../data/announcement_scheduler.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/exam_event.dart';
import '../../domain/entities/event_status.dart';
import '../../../../shared/widgets/app_error_widget.dart';
import '../providers/announcements_providers.dart';
import '../widgets/event_edit_dialog.dart';

/// Màn "Theo dõi thông báo" — danh sách tin (JLPT/MBA…) + cài đặt theo dõi.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(announcementsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi thông báo 🐾'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(announcementsListProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsListProvider);
          await ref.read(announcementsListProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _SettingsCard(),
            const SizedBox(height: 8),
            const _EventsSection(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text('Tin mới từ nguồn chính thức',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            listAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => AppErrorWidget(
                error: e,
                onRetry: () => ref.invalidate(announcementsListProvider),
              ),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chưa có thông báo nào. Kato sẽ báo bạn ngay khi có '
                        'tin mới từ nguồn chính thức 🐾',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      children: [for (final a in items) _AnnouncementTile(a)],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  final Announcement a;
  const _AnnouncementTile(this.a);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tag = switch (a.topic) {
      'jlpt' => ('📣', 'JLPT'),
      'mba' => ('🎓', 'MBA'),
      _ => ('📌', a.topic),
    };
    return Card(
      child: ListTile(
        leading: Text(tag.$1, style: const TextStyle(fontSize: 24)),
        title: Text(a.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.summary.isNotEmpty && a.summary != a.title)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(a.summary),
              ),
            if (a.extractedDates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '📅 Ngày trong tin (chưa kiểm chứng): '
                  '${a.extractedDates.map((d) => '${d.labelVi} ${d.date}').join(' · ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.verified,
                    size: 14,
                    color: a.verified ? scheme.primary : scheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Nguồn: ${a.sourceDomain}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.open_in_new, size: 18),
        isThreeLine: a.summary.isNotEmpty,
        onTap: () => _open(context, a.sourceUrl),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được liên kết nguồn.')),
      );
    }
  }
}

/// Section "Lịch & hạn" — lịch có cấu trúc (đăng ký/thi/kết quả) + trạng thái.
class _EventsSection extends ConsumerWidget {
  const _EventsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(examEventsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('📅 Lịch & hạn',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm mốc'),
              onPressed: () => _openEditor(context, ref, null),
            ),
          ],
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AppErrorWidget(
            error: e,
            onRetry: () => ref.invalidate(examEventsProvider),
          ),
          data: (events) => events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Chưa có lịch nào. Bấm "Thêm mốc" để tự nhập, hoặc lịch '
                    'chuẩn sẽ tự tải khi bật chủ đề tương ứng 🐾',
                  ),
                )
              : Column(children: [for (final e in events) _EventCard(e)]),
        ),
      ],
    );
  }
}

class _EventCard extends ConsumerWidget {
  final ExamEvent event;
  const _EventCard(this.event);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = computeStatus(event, DateTime.now());
    final chipColor = switch (status.level) {
      StatusLevel.danger => Colors.red,
      StatusLevel.warning => Colors.orange,
      StatusLevel.good => Colors.green,
      StatusLevel.neutral => scheme.outline,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(event.sessionLabel,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Sửa mốc',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openEditor(context, ref, event),
                ),
              ],
            ),
            // chip trạng thái tổng
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(status.summaryLabel,
                  style: TextStyle(color: chipColor, fontWeight: FontWeight.w600)),
            ),
            for (final line in status.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line, style: Theme.of(context).textTheme.bodyMedium),
              ),
            if (event.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(event.note,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  event.isTrusted ? Icons.verified : Icons.help_outline,
                  size: 14,
                  color: event.isTrusted ? scheme.primary : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  event.isUserVerified
                      ? 'bạn đã sửa'
                      : event.curated
                          ? 'đã kiểm chứng'
                          : 'tự động',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (event.sourceUrl.isNotEmpty)
                  TextButton(
                    onPressed: () => _open(context, event.sourceUrl),
                    child: Text('Nguồn: ${event.sourceDomain}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được liên kết nguồn.')),
      );
    }
  }
}

/// Mở dialog sửa/thêm mốc; [base] null = thêm mới custom.
Future<void> _openEditor(
    BuildContext context, WidgetRef ref, ExamEvent? base) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => EventEditDialog(base: base),
  );
  if (saved == true) ref.invalidate(examEventsProvider);
}

/// Thẻ cài đặt: bật/tắt, mốc giờ kiểm tra, chủ đề theo dõi, nút test.
class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(announcementPrefsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: prefsAsync.when(
          loading: () => const SizedBox(
              height: 48, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('Lỗi tải cài đặt: ${e.toString()}'),
          data: (prefs) => _SettingsBody(prefs: prefs),
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final AnnouncementPrefs prefs;
  const _SettingsBody({required this.prefs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = AnnouncementPrefsStore();
    final h = prefs.checkMinutes ~/ 60;
    final m = prefs.checkMinutes % 60;

    Future<void> reschedule() async {
      final p = await store.read();
      await scheduleAnnouncementCheck(p);
      ref.invalidate(announcementPrefsProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bật theo dõi thông báo'),
          subtitle: const Text('Kato kiểm tra tin mới mỗi ngày và báo bạn.'),
          value: prefs.enabled,
          onChanged: (v) async {
            await store.setEnabled(v);
            await reschedule();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Giờ kiểm tra mỗi ngày'),
          trailing: Text(
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: h, minute: m),
            );
            if (picked == null) return;
            await store.setCheckMinutes(picked.hour * 60 + picked.minute);
            await reschedule();
          },
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: Text('Chủ đề theo dõi'),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final t in AppConfig.announcementTopics)
              FilterChip(
                label: Text(_topicLabel(t)),
                selected: prefs.topics.contains(t),
                onSelected: (sel) async {
                  final next = List<String>.from(prefs.topics);
                  sel ? next.add(t) : next.remove(t);
                  await store.setTopics(next);
                  ref.invalidate(announcementPrefsProvider);
                  ref.invalidate(announcementsListProvider);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Kiểm tra tin mới ngay'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              int count = -1;
              try {
                count = await checkAnnouncementsNow();
              } catch (_) {}
              ref.invalidate(announcementsListProvider);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    count < 0
                        ? 'Không kết nối được backend. Kiểm tra mạng/URL.'
                        : count == 0
                            ? 'Chưa có tin mới. Kato sẽ báo ngay khi có 🐾'
                            : 'Kato vừa gửi $count tin mới cho bạn 🐾',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _topicLabel(String t) => switch (t) {
        'jlpt' => 'Kỳ thi JLPT',
        'mba' => 'Khoá MBA',
        _ => t,
      };
}
