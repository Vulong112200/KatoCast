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
  /// xác định được (cơn mưa kéo dài quá tầm dự báo ngắn hoặc không áp dụng).
  final DateTime? rainEndsAt;

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
    required this.fromMinutely,
    this.probabilityPct,
  });

  const RainStatus.dry({this.fromMinutely = true})
      : phase = RainPhase.dry,
        changeAt = null,
        minutesUntilChange = null,
        rainEndsAt = null,
        probabilityPct = null;

  const RainStatus.raining({this.fromMinutely = true, this.probabilityPct})
      : phase = RainPhase.raining,
        changeAt = null,
        minutesUntilChange = null,
        rainEndsAt = null;

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
