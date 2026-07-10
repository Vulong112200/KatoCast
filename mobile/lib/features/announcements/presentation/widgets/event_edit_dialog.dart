import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/exam_event.dart';
import '../providers/announcements_providers.dart';

/// Dialog SỬA/THÊM mốc lịch. [base] null = thêm mới (custom). Bản sửa của người
/// dùng luôn ưu tiên & đánh dấu "đã kiểm chứng".
///
/// Trả `true` qua Navigator.pop khi đã lưu/xoá → caller invalidate provider.
class EventEditDialog extends ConsumerStatefulWidget {
  final ExamEvent? base;
  const EventEditDialog({super.key, this.base});

  @override
  ConsumerState<EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends ConsumerState<EventEditDialog> {
  late final TextEditingController _label;
  late final TextEditingController _note;
  DateTime? _regStart, _regEnd, _examDate, _resultDate;

  bool get _isNew => widget.base == null;
  // Nhãn chỉ sửa được với event tự thêm (backend event giữ nhãn gốc).
  bool get _labelEditable => widget.base?.backendId == null;

  @override
  void initState() {
    super.initState();
    final b = widget.base;
    _label = TextEditingController(text: b?.sessionLabel ?? '');
    _note = TextEditingController(text: b?.note ?? '');
    _regStart = b?.regStart;
    _regEnd = b?.regEnd;
    _examDate = b?.examDate;
    _resultDate = b?.resultDate;
  }

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(DateTime? current, ValueChanged<DateTime?> onPick) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) onPick(picked);
  }

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime?> onSet) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        TextButton(
          onPressed: () => _pick(value, (d) => setState(() => onSet(d))),
          child: Text(value == null ? 'Chọn' : _fmt(value)),
        ),
        if (value != null)
          IconButton(
            tooltip: 'Xoá ngày',
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () => setState(() => onSet(null)),
          ),
      ],
    );
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập tên mốc (vd "JLPT Kỳ 7/2026").')),
      );
      return;
    }
    final b = widget.base;
    // Dựng tường minh (không dùng copyWith) để cho phép XOÁ ngày về null.
    final toSave = ExamEvent(
      backendId: b?.backendId,
      overrideId: b?.overrideId,
      topic: b?.topic ?? 'custom',
      sessionLabel: label,
      regStart: _regStart,
      regEnd: _regEnd,
      examDate: _examDate,
      resultDate: _resultDate,
      sourceUrl: b?.sourceUrl ?? '',
      sourceDomain: b?.sourceDomain ?? '',
      curated: b?.curated ?? false,
      note: _note.text.trim(),
    );
    await ref.read(eventRepositoryProvider).saveOverride(toSave);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _revert() async {
    final id = widget.base?.overrideId;
    if (id == null) return;
    await ref.read(eventRepositoryProvider).deleteOverride(id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Thêm mốc' : 'Sửa mốc'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _label,
              enabled: _labelEditable,
              decoration: const InputDecoration(
                labelText: 'Tên mốc',
                hintText: 'vd JLPT Kỳ 7/2026',
              ),
            ),
            const SizedBox(height: 8),
            _dateRow('Đăng ký từ', _regStart, (d) => _regStart = d),
            _dateRow('Đăng ký đến', _regEnd, (d) => _regEnd = d),
            _dateRow('Ngày thi', _examDate, (d) => _examDate = d),
            _dateRow('Ngày kết quả', _resultDate, (d) => _resultDate = d),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            const SizedBox(height: 4),
            Text(
              'Bản bạn sửa sẽ được đánh dấu "đã kiểm chứng" và luôn ưu tiên 🐾',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.base?.overrideId != null)
          TextButton(
            onPressed: _revert,
            child: Text(
              widget.base?.backendId != null ? 'Khôi phục lịch gốc' : 'Xoá',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
