/// Kết quả phân tích trạng thái mưa quanh thời điểm hiện tại.
///
/// Đây là output của use case `AnalyzeRain`, là đầu vào để sinh thông báo.
enum RainPhase {
  /// Trời khô và không thấy mưa trong cửa sổ dự báo.
  dry,

  /// Đang khô nhưng sắp mưa tại [changeAt] (sau [minutesUntilChange] phút).
  rainStartingSoon,

  /// Đang mưa.
  raining,

  /// Đang mưa nhưng sắp tạnh tại [changeAt] (sau [minutesUntilChange] phút).
  rainStoppingSoon,
}

/// Cường độ mưa của một ĐOẠN diễn biến (theo lượng mưa mm/h dự báo).
/// `possible` = giờ đó chỉ có xác suất mưa cao chứ chưa dự báo lượng mưa cụ
/// thể — thông tin "có thể mưa", yếu hơn các mức có mm thật.
enum RainIntensity { possible, light, moderate, heavy }

extension RainIntensityX on RainIntensity {
  /// Nhãn tiếng Việt (viết thường, dùng giữa câu).
  String get label => switch (this) {
        RainIntensity.possible => 'có thể có mưa',
        RainIntensity.light => 'mưa nhỏ',
        RainIntensity.moderate => 'mưa vừa',
        RainIntensity.heavy => 'mưa to',
      };
}

/// Một đoạn diễn biến của cơn mưa sắp tới — các giờ dự báo liền kề CÙNG cường
/// độ được gộp lại; đổi cường độ (hoặc đứt dữ liệu) thì sang đoạn mới. Nhờ đó
/// thông báo mô tả "mưa vừa 17:00–19:00, sau đó mưa nhỏ tới 21:00" thay vì một
/// khối "mưa 17:00–23:00" gây hiểu lầm mưa to suốt.
class RainSegment {
  final DateTime start;

  /// null = đoạn kéo dài quá tầm dữ liệu dự báo (không khẳng định được giờ tạnh).
  final DateTime? end;
  final RainIntensity intensity;

  /// Xác suất mưa lớn nhất (%) trong đoạn; null nếu thiếu dữ liệu pop.
  final int? maxPopPct;

  const RainSegment({
    required this.start,
    this.end,
    required this.intensity,
    this.maxPopPct,
  });
}

/// Câu mô tả diễn biến cơn mưa theo từng đoạn cường độ, ví dụ
/// "mưa vừa ~17:00–19:00, sau đó mưa nhỏ ~19:00–21:00". Trả null nếu < 2 đoạn
/// (cơn mưa đồng nhất → nơi gọi dùng câu "kéo dài đến ..." gọn hơn).
/// Dùng chung cho notification, bản tin và banner trong app để nội dung khớp.
String? describeRainCourse(List<RainSegment> segments) {
  if (segments.length < 2) return null;

  String one(RainSegment s) {
    final end = s.end;
    return end != null
        ? '${s.intensity.label} ~${_hhmm(s.start)}–${_hhmm(end)}'
        : '${s.intensity.label} từ ~${_hhmm(s.start)} (chưa rõ giờ tạnh)';
  }

  // Quá nhiều đoạn → câu dài khó đọc: nêu đoạn đầu + gói phần còn lại.
  if (segments.length > 3) {
    final tailEnd = segments.last.end;
    final tail = tailEnd != null
        ? 'sau đó còn nhiều đợt mưa rải rác tới ~${_hhmm(tailEnd)}'
        : 'sau đó còn nhiều đợt mưa rải rác (chưa rõ giờ tạnh)';
    return '${one(segments.first)}, $tail';
  }

  final buf = StringBuffer(one(segments.first));
  for (var i = 1; i < segments.length; i++) {
    buf.write(', sau đó ${one(segments[i])}');
  }
  return buf.toString();
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class RainStatus {
  final RainPhase phase;

  /// Thời điểm TUYỆT ĐỐI của chuyển trạng thái (mốc timestamp trong dự báo) —
  /// nguồn sự thật cho giờ HH:MM hiển thị. Chỉ có nghĩa với
  /// rainStartingSoon / rainStoppingSoon; null nếu không áp dụng.
  final DateTime? changeAt;

  /// Số phút từ `now` (lúc phân tích) tới [changeAt], đã clamp >= 0.
  /// null nếu không áp dụng.
  final int? minutesUntilChange;

  /// Thời điểm TUYỆT ĐỐI cơn mưa SẮP TỚI dự kiến tạnh (chỉ có nghĩa với
  /// rainStartingSoon — trả lời "mưa kéo dài đến bao giờ"). null nếu không
  /// xác định được (cơn mưa kéo dài quá tầm dự báo hoặc không áp dụng).
  final DateTime? rainEndsAt;

  /// Diễn biến cơn mưa sắp tới theo từng đoạn cường độ (rỗng nếu không áp
  /// dụng / thiếu dữ liệu). Đoạn đầu bắt đầu tại [changeAt]; đoạn cuối kết
  /// thúc tại [rainEndsAt] (end == null nếu vượt tầm dữ liệu).
  final List<RainSegment> segments;

  /// Nguồn dữ liệu suy ra: minutely (chính xác) hay hourly (fallback).
  final bool fromMinutely;

  /// Xác suất mưa (%) tại giờ chứa thời điểm liên quan, suy từ `hourly.pop`
  /// (floor khi minutely đã xác nhận mưa). Chỉ có nghĩa với rainStartingSoon /
  /// raining; null nếu không áp dụng hoặc thiếu dữ liệu giờ.
  final int? probabilityPct;

  const RainStatus({
    required this.phase,
    this.changeAt,
    this.minutesUntilChange,
    this.rainEndsAt,
    this.segments = const [],
    required this.fromMinutely,
    this.probabilityPct,
  });

  const RainStatus.dry({this.fromMinutely = true})
      : phase = RainPhase.dry,
        changeAt = null,
        minutesUntilChange = null,
        rainEndsAt = null,
        segments = const [],
        probabilityPct = null;

  const RainStatus.raining({this.fromMinutely = true, this.probabilityPct})
      : phase = RainPhase.raining,
        changeAt = null,
        minutesUntilChange = null,
        rainEndsAt = null,
        segments = const [];

  bool get isRainingNow =>
      phase == RainPhase.raining || phase == RainPhase.rainStoppingSoon;

  /// Thời lượng (phút) của cơn mưa sắp tới = [rainEndsAt] − [changeAt].
  /// null nếu thiếu một trong hai mốc. Chỉ có nghĩa với rainStartingSoon.
  int? get durationMinutes {
    final start = changeAt;
    final end = rainEndsAt;
    if (start == null || end == null) return null;
    final m = end.difference(start).inMinutes;
    return m > 0 ? m : null;
  }
}
