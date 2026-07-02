import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/note.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_colors.dart';
import 'notes_screen.dart' show kWeekdayShort;

/// Màn tạo / sửa ghi chú. [noteId] null = tạo mới.
class NoteEditScreen extends ConsumerStatefulWidget {
  final int? noteId;
  const NoteEditScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

/// Một dòng checklist đang soạn (giữ controller riêng để gõ mượt).
class _DraftItem {
  final TextEditingController controller;
  bool done;
  _DraftItem(String content, this.done)
      : controller = TextEditingController(text: content);
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final List<_DraftItem> _items = [];

  int _colorIndex = 0;
  bool _pinned = false;
  bool _reminderOn = false;
  DateTime _remindAt = DateTime.now().add(const Duration(hours: 1));
  NoteRepeat _repeat = NoteRepeat.none;
  int _weekdaysMask = 0;

  Note? _original; // note đang sửa (null = tạo mới)
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final id = widget.noteId;
    if (id != null) {
      final state = ref.read(notesControllerProvider);
      final note = state.notes.where((n) => n.id == id).firstOrNull;
      if (note != null) {
        _original = note;
        _titleCtrl.text = note.title;
        _bodyCtrl.text = note.body;
        _colorIndex = note.colorIndex;
        _pinned = note.pinned;
        _reminderOn = note.remindAt != null;
        if (note.remindAt != null) _remindAt = note.remindAt!;
        _repeat = note.repeat;
        _weekdaysMask = note.weekdaysMask;
        for (final it in state.items[id] ?? const <NoteItem>[]) {
          _items.add(_DraftItem(it.content, it.done));
        }
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    for (final it in _items) {
      it.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Ghi chú mới' : 'Sửa ghi chú'),
        actions: [
          IconButton(
            tooltip: 'Lưu',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nội dung (tuỳ chọn)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Checklist'),
          for (var i = 0; i < _items.length; i++) _itemRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Thêm mục'),
              onPressed: () =>
                  setState(() => _items.add(_DraftItem('', false))),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Màu'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < kNoteColors.length; i++)
                ChoiceChip(
                  label: i == 0
                      ? const Text('Mặc định')
                      : const SizedBox(width: 24, height: 16),
                  selected: _colorIndex == i,
                  backgroundColor:
                      i == 0 ? null : noteCardColor(context, i),
                  selectedColor: i == 0 ? null : noteCardColor(context, i),
                  onSelected: (_) => setState(() => _colorIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('Nhắc hẹn'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hẹn giờ thông báo'),
            subtitle: _reminderOn ? Text(_reminderSummary()) : null,
            value: _reminderOn,
            onChanged: (v) => setState(() => _reminderOn = v),
          ),
          if (_reminderOn) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                      '${_remindAt.day.toString().padLeft(2, '0')}/'
                      '${_remindAt.month.toString().padLeft(2, '0')}/'
                      '${_remindAt.year}'),
                  onPressed: _repeat == NoteRepeat.none ? _pickDate : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(
                      '${_remindAt.hour.toString().padLeft(2, '0')}:'
                      '${_remindAt.minute.toString().padLeft(2, '0')}'),
                  onPressed: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<NoteRepeat>(
              segments: const [
                ButtonSegment(
                    value: NoteRepeat.none, label: Text('Một lần')),
                ButtonSegment(
                    value: NoteRepeat.daily, label: Text('Hằng ngày')),
                ButtonSegment(
                    value: NoteRepeat.weekly, label: Text('Hằng tuần')),
              ],
              selected: {_repeat},
              onSelectionChanged: (s) => setState(() => _repeat = s.first),
            ),
            if (_repeat == NoteRepeat.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (var wd = 1; wd <= 7; wd++)
                    FilterChip(
                      label: Text(kWeekdayShort[wd - 1]),
                      selected: _weekdaysMask & (1 << (wd - 1)) != 0,
                      onSelected: (v) => setState(() {
                        _weekdaysMask = v
                            ? _weekdaysMask | (1 << (wd - 1))
                            : _weekdaysMask & ~(1 << (wd - 1));
                      }),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ghim lên thanh thông báo'),
            subtitle: const Text(
                'Hiện cố định trên khay thông báo, không mất khi "Xoá tất '
                'cả"; chỉ gỡ khi nhấn "Đã đọc".'),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_validationError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600));

  Widget _itemRow(int i) {
    final it = _items[i];
    return Row(children: [
      Checkbox(
        value: it.done,
        onChanged: (v) => setState(() => it.done = v ?? false),
      ),
      Expanded(
        child: TextField(
          controller: it.controller,
          decoration: const InputDecoration(
            hintText: 'Mục cần làm…',
            isDense: true,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Xoá mục',
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => setState(() => _items.removeAt(i).controller.dispose()),
      ),
    ]);
  }

  String _reminderSummary() {
    final hm = '${_remindAt.hour.toString().padLeft(2, '0')}:'
        '${_remindAt.minute.toString().padLeft(2, '0')}';
    switch (_repeat) {
      case NoteRepeat.none:
        return 'Một lần lúc $hm ngày '
            '${_remindAt.day.toString().padLeft(2, '0')}/'
            '${_remindAt.month.toString().padLeft(2, '0')}';
      case NoteRepeat.daily:
        return 'Hằng ngày lúc $hm';
      case NoteRepeat.weekly:
        final days = [
          for (var wd = 1; wd <= 7; wd++)
            if (_weekdaysMask & (1 << (wd - 1)) != 0) kWeekdayShort[wd - 1],
        ];
        return days.isEmpty
            ? 'Hằng tuần — hãy chọn thứ'
            : 'Hằng tuần ${days.join(', ')} lúc $hm';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _remindAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _remindAt = DateTime(picked.year, picked.month,
          picked.day, _remindAt.hour, _remindAt.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_remindAt),
    );
    if (picked != null) {
      setState(() => _remindAt = DateTime(_remindAt.year, _remindAt.month,
          _remindAt.day, picked.hour, picked.minute));
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final items = <NoteItem>[
      for (final it in _items)
        if (it.controller.text.trim().isNotEmpty)
          NoteItem(
            noteId: _original?.id ?? 0, // datasource ghi lại theo id thật
            content: it.controller.text.trim(),
            done: it.done,
            seq: 0, // replaceItems đánh seq theo thứ tự list
          ),
    ];

    // Validate.
    if (title.isEmpty && body.isEmpty && items.isEmpty) {
      setState(() => _validationError =
          'Ghi chú trống — hãy nhập tiêu đề, nội dung hoặc checklist.');
      return;
    }
    if (_reminderOn && _repeat == NoteRepeat.weekly && _weekdaysMask == 0) {
      setState(
          () => _validationError = 'Nhắc hằng tuần: hãy chọn ít nhất 1 thứ.');
      return;
    }
    if (_reminderOn &&
        _repeat == NoteRepeat.none &&
        !_remindAt.isAfter(DateTime.now())) {
      setState(() => _validationError =
          'Thời điểm nhắc một lần phải ở tương lai.');
      return;
    }

    final now = DateTime.now();
    final note = Note(
      id: _original?.id,
      title: title.isEmpty ? 'Ghi chú' : title,
      body: body,
      colorIndex: _colorIndex,
      pinned: _pinned,
      done: _original?.done ?? false,
      remindAt: _reminderOn ? _remindAt : null,
      repeat: _reminderOn ? _repeat : NoteRepeat.none,
      weekdaysMask: _reminderOn && _repeat == NoteRepeat.weekly
          ? _weekdaysMask
          : 0,
      createdAt: _original?.createdAt ?? now,
      updatedAt: now,
    );

    await ref.read(notesControllerProvider.notifier).save(note, items);
    if (mounted) context.pop();
  }
}
