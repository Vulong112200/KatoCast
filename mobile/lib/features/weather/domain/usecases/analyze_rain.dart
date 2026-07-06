import 'dart:math' as math;

import '../../../../core/config/app_config.dart';
import '../entities/hourly.dart';
import '../entities/minutely.dart';
import '../entities/rain_status.dart';
import '../entities/weather.dart';

/// Use case CỐT LÕI: phân tích khi nào bắt đầu/kết thúc mưa.
///
/// Ưu tiên `minutely` (nowcast 15'/1'). Nếu không có thì fallback sang
/// `hourly` (xác suất + lượng mưa). Mọi phép tính thời gian neo vào [now]
/// (mặc định `DateTime.now()`), KHÔNG neo vào mốc đầu của dữ liệu dự báo —
/// nhờ đó giờ HH:MM và số phút vẫn đúng kể cả khi dữ liệu là cache cũ vài
/// phút. Logic thuần (không phụ thuộc Flutter) để dễ unit-test các ca biên.
class AnalyzeRain {
  const AnalyzeRain();

  static const double _threshold = AppConfig.rainThresholdMmH;
  static const int _dryStreak = AppConfig.dryStreakToConfirmStop;
  static const double _popThreshold = AppConfig.rainAlertPopThreshold;

  /// Mốc minutely cũ hơn `now` quá ngưỡng này coi như không còn đại diện cho
  /// hiện tại (slot nowcast dài nhất là 15').
  static const Duration _minutelySlot = Duration(minutes: 15);

  RainStatus call(WeatherData data, {DateTime? now}) {
    final ref = now ?? DateTime.now();

    // Bỏ các điểm dự báo đã thuộc quá khứ (dữ liệu cache cũ): giữ slot/giờ
    // đang chứa `ref` trở đi.
    final minutely = _relevantMinutely(data.minutely, ref);
    final hourly = _relevantHourly(data.hourly, ref);

    final base = minutely.isNotEmpty
        ? _fromMinutely(minutely, ref)
        : _fromHourly(hourly, ref);

    // Xác suất chỉ có nghĩa khi sắp mưa / đang mưa (dry & sắp tạnh không
    // hiển thị % ở đâu cả).
    if (base.phase != RainPhase.rainStartingSoon &&
        base.phase != RainPhase.raining) {
      return base;
    }
    final pct = _probabilityPct(
      hourly,
      eventTime: base.changeAt ?? ref,
      minutelyConfirmed: base.fromMinutely,
    );
    if (pct == null) return base;
    return RainStatus(
      phase: base.phase,
      changeAt: base.changeAt,
      minutesUntilChange: base.minutesUntilChange,
      rainEndsAt: base.rainEndsAt,
      fromMinutely: base.fromMinutely,
      probabilityPct: pct,
    );
  }

  /// Giữ các mốc minutely từ slot hiện tại trở đi. Trả rỗng nếu toàn bộ chuỗi
  /// đã quá cũ so với [ref] (→ để caller fallback sang hourly).
  List<MinutelyForecast> _relevantMinutely(
    List<MinutelyForecast> minutely,
    DateTime ref,
  ) {
    if (minutely.isEmpty) return const [];
    // Mốc cuối cùng có time <= ref là slot đang chứa "bây giờ".
    var start = 0;
    for (var i = 0; i < minutely.length; i++) {
      if (minutely[i].time.isAfter(ref)) break;
      start = i;
    }
    // Slot "hiện tại" đã kết thúc quá lâu → chuỗi không nói gì về bây giờ.
    if (ref.difference(minutely[start].time) > _minutelySlot) return const [];
    return minutely.sublist(start);
  }

  /// Giữ các giờ có khối [time, time+1h) còn giao với hiện tại/tương lai.
  List<HourlyForecast> _relevantHourly(
    List<HourlyForecast> hourly,
    DateTime ref,
  ) {
    return hourly
        .where((h) => h.time.add(const Duration(hours: 1)).isAfter(ref))
        .toList();
  }

  // --- Phân tích theo chuỗi dự báo ngắn hạn ---
  //
  // Độc lập với độ phân giải: dùng MỐC THỜI GIAN (time) so với [ref], nên
  // chạy đúng cho cả `minutely` 1 phút (One Call 3.0) lẫn nowcast 15 phút
  // (One Call 4.0 — đã chuẩn hoá về cùng entity ở data layer).
  RainStatus _fromMinutely(List<MinutelyForecast> minutely, DateTime ref) {
    final rainingNow = minutely.first.precipitationMmH > _threshold;

    if (!rainingNow) {
      // Đang khô → tìm mốc đầu tiên có mưa.
      for (var i = 1; i < minutely.length; i++) {
        if (minutely[i].precipitationMmH > _threshold) {
          return RainStatus(
            phase: RainPhase.rainStartingSoon,
            changeAt: minutely[i].time,
            minutesUntilChange: _minutesFrom(ref, minutely[i].time),
            // Quét tiếp từ lúc bắt đầu mưa để biết khi nào tạnh (kéo dài đến).
            rainEndsAt: _minutelyRainEnd(minutely, i),
            fromMinutely: true,
          );
        }
      }
      return const RainStatus.dry();
    }

    // Đang mưa → tìm mốc bắt đầu "khô bền vững" (>= _dryStreak mốc khô liên
    // tiếp) để tránh báo tạnh sai do 1 mốc lặng giữa cơn mưa.
    for (var i = 1; i < minutely.length; i++) {
      if (minutely[i].precipitationMmH <= _threshold) {
        if (_isDrySustained(minutely, i)) {
          return RainStatus(
            phase: RainPhase.rainStoppingSoon,
            changeAt: minutely[i].time,
            minutesUntilChange: _minutesFrom(ref, minutely[i].time),
            fromMinutely: true,
          );
        }
      }
    }
    return const RainStatus.raining();
  }

  /// Số phút từ [ref] tới [at], clamp >= 0 (mốc chuyển biến nằm trong slot
  /// hiện tại → coi là "ngay bây giờ").
  int _minutesFrom(DateTime ref, DateTime at) =>
      math.max(0, at.difference(ref).inMinutes);

  /// Từ mốc [start], kiểm tra có đủ chuỗi khô liên tiếp không (xét tới hết
  /// cửa sổ nếu dữ liệu ngắn hơn _dryStreak).
  bool _isDrySustained(List<MinutelyForecast> minutely, int start) {
    final end = (start + _dryStreak).clamp(0, minutely.length);
    for (var j = start; j < end; j++) {
      if (minutely[j].precipitationMmH > _threshold) return false;
    }
    return true;
  }

  /// Từ mốc bắt đầu mưa [rainStart], quét tiếp tìm mốc "khô bền vững" đầu tiên
  /// → thời điểm cơn mưa tạnh. null nếu tới hết cửa sổ vẫn còn mưa (cơn mưa kéo
  /// dài quá tầm dự báo ngắn — không khẳng định được giờ tạnh).
  DateTime? _minutelyRainEnd(List<MinutelyForecast> minutely, int rainStart) {
    for (var i = rainStart + 1; i < minutely.length; i++) {
      if (minutely[i].precipitationMmH <= _threshold &&
          _isDrySustained(minutely, i)) {
        return minutely[i].time;
      }
    }
    return null;
  }

  // --- Fallback theo giờ ---
  RainStatus _fromHourly(List<HourlyForecast> hourly, DateTime ref) {
    if (hourly.isEmpty) return const RainStatus.dry(fromMinutely: false);

    bool isWet(HourlyForecast h) =>
        h.rainMm > _threshold || h.pop >= _popThreshold;

    // Giờ đầu chỉ đại diện "bây giờ" nếu khối giờ của nó đang chứa ref.
    final rainingNow = !hourly.first.time.isAfter(ref) && isWet(hourly.first);

    if (!rainingNow) {
      for (var i = 0; i < hourly.length; i++) {
        if (isWet(hourly[i])) {
          final minutes = _minutesFrom(ref, hourly[i].time);
          // Onset quá xa → chưa coi là "sắp mưa" (tránh báo quá sớm).
          if (minutes > AppConfig.rainSoonHorizonMinutes) {
            return const RainStatus.dry(fromMinutely: false);
          }
          return RainStatus(
            phase: RainPhase.rainStartingSoon,
            changeAt: hourly[i].time,
            minutesUntilChange: minutes,
            // Giờ "khô" đầu tiên sau đợt mưa = thời điểm dự kiến tạnh.
            rainEndsAt: _hourlyRainEnd(hourly, i, isWet),
            fromMinutely: false,
          );
        }
      }
      return const RainStatus.dry(fromMinutely: false);
    }

    for (var i = 1; i < hourly.length; i++) {
      if (!isWet(hourly[i])) {
        return RainStatus(
          phase: RainPhase.rainStoppingSoon,
          changeAt: hourly[i].time,
          minutesUntilChange: _minutesFrom(ref, hourly[i].time),
          fromMinutely: false,
        );
      }
    }
    return const RainStatus.raining(fromMinutely: false);
  }

  /// Từ giờ bắt đầu mưa [rainStart], tìm giờ "khô" đầu tiên → thời điểm tạnh.
  /// null nếu tới hết dữ liệu giờ vẫn còn ướt.
  DateTime? _hourlyRainEnd(
    List<HourlyForecast> hourly,
    int rainStart,
    bool Function(HourlyForecast) isWet,
  ) {
    for (var i = rainStart + 1; i < hourly.length; i++) {
      if (!isWet(hourly[i])) return hourly[i].time;
    }
    return null;
  }

  /// Xác suất mưa (%) tại GIỜ CHỨA [eventTime] (so timestamp, không chia 60).
  /// [minutelyConfirmed] = nowcast đã thấy mưa → floor xác suất để không mâu
  /// thuẫn kiểu "đang mưa, khả năng 40%". null nếu không có nguồn nào.
  int? _probabilityPct(
    List<HourlyForecast> hourly, {
    required DateTime eventTime,
    required bool minutelyConfirmed,
  }) {
    int? pct;
    for (final h in hourly) {
      final endsAt = h.time.add(const Duration(hours: 1));
      if (!eventTime.isBefore(h.time) && eventTime.isBefore(endsAt)) {
        pct = (h.pop * 100).round();
        break;
      }
    }
    // Fallback: không có giờ nào chứa đúng eventTime (vd eventTime vượt tầm
    // hourly, hoặc lệch khối giờ) → dùng pop của giờ liên quan gần nhất để %
    // vẫn hiển thị thay vì rỗng.
    if (pct == null && hourly.isNotEmpty) {
      var nearest = hourly.first;
      for (final h in hourly) {
        if ((h.time.difference(eventTime)).abs() <
            (nearest.time.difference(eventTime)).abs()) {
          nearest = h;
        }
      }
      pct = (nearest.pop * 100).round();
    }
    if (minutelyConfirmed) {
      const floor = AppConfig.minutelyProbabilityFloorPct;
      pct = pct == null ? floor : math.max(pct, floor);
    }
    return pct;
  }
}
