import 'exam_event.dart';

/// Mức độ để tô màu chip (UI ánh xạ sang màu cụ thể).
enum StatusLevel { neutral, good, warning, danger }

/// Kết quả tính trạng thái của một [ExamEvent] tại thời điểm [now].
class EventStatus {
  /// Câu tóm tắt ngắn (vd "Đã hết hạn đăng ký · Đã thi").
  final String summaryLabel;

  /// Mức độ nổi bật để chọn màu chip.
  final StatusLevel level;

  /// Các dòng chi tiết theo từng mốc (đăng ký/thi/kết quả).
  final List<String> lines;

  const EventStatus({
    required this.summaryLabel,
    required this.level,
    required this.lines,
  });
}

int _dayDiff(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Tính trạng thái còn hạn/hết hạn từ các mốc ngày (so với [now]).
///
/// Ưu tiên nêu hành động gần nhất: đang mở đăng ký → còn thi → đã qua.
EventStatus computeStatus(ExamEvent e, DateTime now) {
  final parts = <String>[];
  final lines = <String>[];
  StatusLevel level = StatusLevel.neutral;

  // ── Đăng ký ────────────────────────────────────────────────────────────
  // regFocus = đăng ký đang là mối quan tâm chính (chưa mở / đang mở) → ngày thi
  // (còn xa) không được nâng màu, tránh báo "xanh" khi thật ra phải CHỜ đăng ký.
  bool regFocus = false;
  String? regPart;
  if (e.regStart != null || e.regEnd != null) {
    if (e.regStart != null && _dayDiff(now, e.regStart!) > 0) {
      final d = _dayDiff(now, e.regStart!);
      regPart = 'Đăng ký mở sau $d ngày';
      level = StatusLevel.neutral;
      regFocus = true;
    } else if (e.regEnd != null && _dayDiff(now, e.regEnd!) < 0) {
      regPart = 'Đã hết hạn đăng ký';
    } else {
      // đang trong khoảng đăng ký
      final left = e.regEnd != null ? _dayDiff(now, e.regEnd!) : null;
      regPart = left != null ? 'Đang mở đăng ký (còn $left ngày)' : 'Đang mở đăng ký';
      level = (left != null && left <= 3)
          ? StatusLevel.danger
          : (left != null && left <= 7)
              ? StatusLevel.warning
              : StatusLevel.good;
      regFocus = true;
    }
    lines.add(_regLine(e));
    parts.add(regPart);
  }

  // ── Thi ──────────────────────────────────────────────────────────────────
  if (e.examDate != null) {
    final d = _dayDiff(now, e.examDate!);
    if (d > 0) {
      parts.add('Còn $d ngày đến ngày thi');
      // chỉ nâng mức nếu đăng ký không còn là mối quan tâm chính
      if (!regFocus && level == StatusLevel.neutral) {
        level = d <= 3 ? StatusLevel.warning : StatusLevel.good;
      }
    } else if (d == 0) {
      parts.add('Thi hôm nay');
      level = StatusLevel.warning;
    } else {
      parts.add('Đã thi');
    }
    lines.add('Thi: ${_fmt(e.examDate)}');
  }

  // ── Kết quả ────────────────────────────────────────────────────────────
  if (e.resultDate != null) {
    if (_dayDiff(now, e.resultDate!) <= 0) {
      parts.add('Đã có kết quả');
      if (level == StatusLevel.neutral) level = StatusLevel.good;
    }
    lines.add('Kết quả: ${_fmt(e.resultDate)}');
  }

  final summary = parts.isEmpty ? 'Chưa có mốc thời gian' : parts.join(' · ');
  return EventStatus(summaryLabel: summary, level: level, lines: lines);
}

String _regLine(ExamEvent e) {
  if (e.regStart != null && e.regEnd != null) {
    return 'Đăng ký: ${_fmt(e.regStart)} – ${_fmt(e.regEnd)}';
  }
  if (e.regEnd != null) return 'Hạn đăng ký: ${_fmt(e.regEnd)}';
  return 'Mở đăng ký: ${_fmt(e.regStart)}';
}

/// dd/mm/yyyy — hiển thị kiểu VN.
String _fmt(DateTime? d) {
  if (d == null) return '—';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}
