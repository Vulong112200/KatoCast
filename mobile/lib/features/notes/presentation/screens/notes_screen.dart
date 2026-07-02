import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_drawer.dart';
import '../../domain/entities/note.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_colors.dart';

/// Nhãn thứ ngắn theo DateTime.weekday (1=Thứ 2 … 7=CN).
const List<String> kWeekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Mô tả lịch nhắc của note để hiển thị trên chip.
String describeReminder(Note n) {
  final at = n.remindAt;
  if (at == null) return '';
  final hm = '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  switch (n.repeat) {
    case NoteRepeat.none:
      return '${at.day.toString().padLeft(2, '0')}/'
          '${at.month.toString().padLeft(2, '0')} $hm';
    case NoteRepeat.daily:
      return '$hm hằng ngày';
    case NoteRepeat.weekly:
      final days = [
        for (var wd = 1; wd <= 7; wd++)
          if (n.weekdaysMask & (1 << (wd - 1)) != 0) kWeekdayShort[wd - 1],
      ];
      return '${days.join(', ')} $hm';
  }
}

/// Màn danh sách ghi chú: tìm kiếm + tab đang hoạt động / đã xong.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notesControllerProvider);
    final controller = ref.read(notesControllerProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('Ghi chú'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBar(
                    hintText: 'Tìm ghi chú…',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: controller.setQuery,
                  ),
                ),
                TabBar(tabs: [
                  Tab(text: 'Ghi chú (${state.activeNotes.length})'),
                  Tab(text: 'Đã xong (${state.doneNotes.length})'),
                ]),
              ],
            ),
          ),
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _NoteList(
                  notes: state.activeNotes,
                  emptyText: state.query.isEmpty
                      ? 'Chưa có ghi chú.\nNhấn + để tạo ghi chú đầu tiên.'
                      : 'Không tìm thấy ghi chú phù hợp.',
                  doneTab: false,
                ),
                _NoteList(
                  notes: state.doneNotes,
                  emptyText: 'Chưa có ghi chú nào hoàn thành.',
                  doneTab: true,
                ),
              ]),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Thêm ghi chú',
          onPressed: () => context.push('/notes/edit'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _NoteList extends ConsumerWidget {
  final List<Note> notes;
  final String emptyText;
  final bool doneTab;
  const _NoteList({
    required this.notes,
    required this.emptyText,
    required this.doneTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (notes.isEmpty) {
      return Center(
        child: Text(emptyText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: notes.length,
      itemBuilder: (context, i) => _NoteCard(note: notes[i], doneTab: doneTab),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final bool doneTab;
  const _NoteCard({required this.note, required this.doneTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notesControllerProvider);
    final controller = ref.read(notesControllerProvider.notifier);
    final items = state.items[note.id] ?? const <NoteItem>[];
    final doneCount = items.where((it) => it.done).length;
    final reminder = describeReminder(note);

    return Card(
      color: noteCardColor(context, note.colorIndex),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/notes/edit', extra: note.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (note.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(note.body,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                    if (items.isNotEmpty || reminder.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (items.isNotEmpty)
                            _chip(context, Icons.checklist,
                                '$doneCount/${items.length}'),
                          if (reminder.isNotEmpty)
                            _chip(context, Icons.alarm, reminder),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!doneTab)
                IconButton(
                  tooltip: note.pinned
                      ? 'Bỏ ghim khỏi thanh thông báo'
                      : 'Ghim lên thanh thông báo',
                  icon: Icon(
                      note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  onPressed: () => controller.togglePin(note),
                ),
              PopupMenuButton<String>(
                onSelected: (v) => _onMenu(context, controller, v),
                itemBuilder: (_) => [
                  if (!doneTab)
                    const PopupMenuItem(
                        value: 'done', child: Text('Đánh dấu đã xong')),
                  if (doneTab)
                    const PopupMenuItem(
                        value: 'restore', child: Text('Khôi phục')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(doneTab ? 'Xoá vĩnh viễn' : 'Xoá')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    NotesController controller,
    String action,
  ) async {
    switch (action) {
      case 'done':
        await controller.markDone(note);
      case 'restore':
        await controller.restore(note);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xoá ghi chú?'),
            content: Text('"${note.title}" sẽ bị xoá vĩnh viễn '
                '(kèm lịch nhắc và ghim nếu có).'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Huỷ')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Xoá')),
            ],
          ),
        );
        if (ok == true) await controller.delete(note);
    }
  }
}
