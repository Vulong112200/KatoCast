/// Kết quả phân tích trạng thái mưa quanh thời điểm hiện tại.
///
/// Đây là output của use case `AnalyzeRain`, là đầu vào để sinh thông báo.
enum RainPhase {
  /// Trời khô và không thấy mưa trong cửa sổ dự báo.
  dry,

  /// Đang khô nhưng sắp mưa trong [minutesUntilChange] phút.
  rainStartingSoon,

  /// Đang mưa.
  raining,

  /// Đang mưa nhưng sắp tạnh trong [minutesUntilChange] phút.
  rainStoppingSoon,
}

class RainStatus {
  final RainPhase phase;

  /// Số phút tới khi xảy ra chuyển trạng thái (chỉ có nghĩa với
  /// rainStartingSoon / rainStoppingSoon). null nếu không áp dụng.
  final int? minutesUntilChange;

  /// Nguồn dữ liệu suy ra: minutely (chính xác) hay hourly (fallback).
  final bool fromMinutely;

  /// Xác suất mưa (%) quanh thời điểm liên quan, suy từ `hourly.pop`. null nếu
  /// không có dữ liệu giờ để ước lượng.
  final int? probabilityPct;

  const RainStatus({
    required this.phase,
    this.minutesUntilChange,
    required this.fromMinutely,
    this.probabilityPct,
  });

  const RainStatus.dry({this.fromMinutely = true})
      : phase = RainPhase.dry,
        minutesUntilChange = null,
        probabilityPct = null;

  const RainStatus.raining({this.fromMinutely = true, this.probabilityPct})
      : phase = RainPhase.raining,
        minutesUntilChange = null;

  bool get isRainingNow =>
      phase == RainPhase.raining || phase == RainPhase.rainStoppingSoon;
}
