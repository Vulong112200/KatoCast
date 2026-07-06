/// Phân loại chỉ số UV thành mức + lời khuyên dễ hiểu cho người dùng.
///
/// Theo thang WHO (0–2 thấp … 11+ cực kỳ cao). Thuần (không phụ thuộc Flutter)
/// nên dùng chung được cho bản tin, thông báo và UI, kể cả ở background isolate.
/// Tái dùng bởi `BuildDailyDigest`, `BuildWeatherAlerts` và card thời tiết.
enum UvBand { low, moderate, high, veryHigh, extreme }

class UvAdvice {
  /// Giá trị UV làm tròn (dùng hiển thị "UV 8").
  final int level;

  /// Nhóm mức (để tô màu / so sánh ngưỡng).
  final UvBand band;

  /// Nhãn tiếng Việt: "Thấp", "Trung bình", "Cao", "Rất cao", "Cực kỳ cao".
  final String label;

  /// Lời khuyên hành động cụ thể, dễ hiểu.
  final String advice;

  const UvAdvice({
    required this.level,
    required this.band,
    required this.label,
    required this.advice,
  });

  /// Có đáng nhắc chống nắng không (từ mức "Trung bình" trở lên).
  bool get needsProtection => band != UvBand.low;

  static UvAdvice classify(double uvi) {
    final level = uvi.round();
    if (uvi < 3) {
      return UvAdvice(
        level: level,
        band: UvBand.low,
        label: 'Thấp',
        advice: 'Tia UV yếu, an toàn khi ra ngoài, không cần biện pháp đặc biệt.',
      );
    }
    if (uvi < 6) {
      return UvAdvice(
        level: level,
        band: UvBand.moderate,
        label: 'Trung bình',
        advice: 'Nên đội mũ và đeo kính râm khi ra ngoài buổi trưa.',
      );
    }
    if (uvi < 8) {
      return UvAdvice(
        level: level,
        band: UvBand.high,
        label: 'Cao',
        advice: 'Thoa kem chống nắng, đội mũ, tránh nắng gắt khoảng 10–15h.',
      );
    }
    if (uvi < 11) {
      return UvAdvice(
        level: level,
        band: UvBand.veryHigh,
        label: 'Rất cao',
        advice: 'Hạn chế ra ngoài 10–16h; mặc áo chống nắng, kem SPF cao, '
            'đội mũ rộng vành.',
      );
    }
    return UvAdvice(
      level: level,
      band: UvBand.extreme,
      label: 'Cực kỳ cao',
      advice: 'Nguy hiểm — tránh ra nắng, che chắn tối đa nếu buộc phải ra ngoài.',
    );
  }
}
