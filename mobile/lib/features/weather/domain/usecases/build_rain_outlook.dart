import '../../../../core/config/app_config.dart';
import '../entities/hourly.dart';
import '../entities/weather.dart';

/// Use case: dựng câu tóm tắt khả năng mưa CẢ NGÀY hôm nay theo buổi
/// (đêm / sáng / chiều / tối) từ dự báo `hourly`.
///
/// Khác với [AnalyzeRain] (chỉ nhìn ~2h tới, dùng cho cảnh báo tức thời), use
/// case này quét toàn bộ các giờ còn lại của hôm nay để trả lời câu hỏi "hôm
/// nay có mưa không, mấy giờ mưa" trong bản tin. Các giờ mưa KHÔNG liên tục
/// được tách thành từng đợt riêng (không gộp thành 1 khung dài gây hiểu lầm
/// mưa suốt). Thuần (không phụ thuộc Flutter) → chạy được ở background
/// isolate và dễ unit-test.
class BuildRainOutlook {
  const BuildRainOutlook();

  static const double _popThreshold = AppConfig.rainOutlookPopThreshold;
  static const double _rainThreshold = AppConfig.rainThresholdMmH;

  /// Các buổi trong ngày: [nhãn, giờ bắt đầu (bao gồm), giờ kết thúc (loại
  /// trừ)] — phủ đủ 0–24h để mưa khuya/rạng sáng không bị bỏ rơi.
  static const List<(String, int, int)> _periods = [
    ('Đêm', 0, 5),
    ('Sáng', 5, 11),
    ('Chiều', 11, 17),
    ('Tối', 17, 24),
  ];

  /// Trả câu mô tả khả năng mưa hôm nay; null nếu không còn giờ nào của hôm nay
  /// trong dữ liệu (vd đã khuya) → để nơi gọi bỏ qua dòng này.
  String? call(WeatherData data, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final hourFloor = DateTime(ref.year, ref.month, ref.day, ref.hour);

    // Giờ thuộc HÔM NAY và không nằm trước giờ hiện tại.
    final today = data.hourly
        .where((h) =>
            h.time.year == ref.year &&
            h.time.month == ref.month &&
            h.time.day == ref.day &&
            !h.time.isBefore(hourFloor))
        .toList();
    if (today.isEmpty) return null;

    final rainy = <String>[]; // "chiều có mưa (~14:00–16:00, khả năng ~70%)"
    final dry = <String>[]; // nhãn buổi khô (có dữ liệu nhưng không mưa)

    for (final (label, start, end) in _periods) {
      final hrs =
          today.where((h) => h.time.hour >= start && h.time.hour < end).toList();
      if (hrs.isEmpty) continue; // buổi đã qua / ngoài dữ liệu

      final wet = hrs.where(_isWet).toList();
      if (wet.isEmpty) {
        dry.add(label.toLowerCase());
        continue;
      }

      rainy.add('${label.toLowerCase()} có mưa ${_describeSegments(wet)}');
    }

    if (rainy.isEmpty) return 'Hôm nay ít khả năng mưa.';

    var sentence = '${_capitalize(rainy.join('; '))}.';
    if (dry.isNotEmpty) {
      sentence += ' ${_capitalize(dry.join(' & '))} khô ráo.';
    }
    return sentence;
  }

  /// Gom các giờ ướt LIỀN KỀ (cách nhau ≤ 1h) thành từng đợt và mô tả.
  /// 1–2 đợt: nêu khung giờ + khả năng từng đợt; >2 đợt: gộp thành
  /// "rải rác nhiều đợt" cho câu gọn.
  String _describeSegments(List<HourlyForecast> wet) {
    final segments = <List<HourlyForecast>>[];
    for (final h in wet) {
      if (segments.isNotEmpty &&
          h.time.difference(segments.last.last.time) <=
              const Duration(hours: 1)) {
        segments.last.add(h);
      } else {
        segments.add([h]);
      }
    }

    if (segments.length > 2) {
      var maxPop = 0.0;
      for (final h in wet) {
        if (h.pop > maxPop) maxPop = h.pop;
      }
      return 'rải rác nhiều đợt (khả năng tới ~${(maxPop * 100).round()}%)';
    }

    final parts = segments.map((seg) {
      final from = seg.first.time;
      // Kết thúc + 1h vì mỗi mốc đại diện cho cả khối giờ đó.
      final to = seg.last.time.add(const Duration(hours: 1));
      var maxPop = seg.first.pop;
      for (final h in seg) {
        if (h.pop > maxPop) maxPop = h.pop;
      }
      return '~${_clock(from)}–${_clock(to)}, '
          'khả năng ~${(maxPop * 100).round()}%';
    });
    return '(${parts.join(' và ')})';
  }

  bool _isWet(HourlyForecast h) =>
      h.pop >= _popThreshold || h.rainMm > _rainThreshold;

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
