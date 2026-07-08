import 'dart:math' as math;

import '../../../../core/config/app_config.dart';
import '../entities/hourly.dart';
import '../entities/minutely.dart';
import '../entities/rain_status.dart';
import '../entities/weather.dart';
import '../entities/weather_condition.dart';

/// Use case CỐT LÕI: phân tích khi nào bắt đầu/kết thúc mưa.
///
/// Kết hợp 3 nguồn theo độ tin cậy cho từng câu hỏi:
/// - `current` (quan trắc): nguồn sự thật cho "ĐANG mưa hay không" — nowcast
///   hay báo trễ/bỏ sót, nếu chỉ tin nowcast thì trời mưa rồi app vẫn im lặng.
/// - `minutely` (nowcast 15'/1'): chính xác phút cho onset/giờ tạnh TRONG cửa
///   sổ ngắn (~1–2h).
/// - `hourly`: onset xa hơn cửa sổ nowcast + DIỄN BIẾN cường độ từng giờ
///   (mưa nhỏ/vừa/to) → `RainStatus.segments`. Khi nowcast bảo khô nhưng
///   hourly có tín hiệu MẠNH (mm thật + pop cao) thì vẫn cảnh báo sớm.
///
/// Mọi phép tính thời gian neo vào [now] (mặc định `DateTime.now()`), KHÔNG
/// neo vào mốc đầu của dữ liệu dự báo — nhờ đó giờ HH:MM và số phút vẫn đúng
/// kể cả khi dữ liệu là cache cũ vài phút. Logic thuần (không phụ thuộc
/// Flutter) để dễ unit-test các ca biên.
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

    var base = minutely.isNotEmpty
        ? _fromMinutely(minutely, hourly, ref)
        : _fromHourly(hourly, ref);

    // Quan trắc `current` nói ĐANG MƯA nhưng dự báo ngắn bảo khô/mới sắp mưa
    // → tin quan trắc. Không có bước này, nowcast bỏ sót sẽ khiến app im lặng
    // dù trời đã mưa (người dùng chỉ nhận thông báo "tình hình" đến muộn).
    if (!base.isRainingNow && _obsIndicatesRain(data.current, ref)) {
      base = RainStatus.raining(fromMinutely: base.fromMinutely);
    }

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
      segments: base.segments,
      fromMinutely: base.fromMinutely,
      probabilityPct: pct,
    );
  }

  /// Quan trắc hiện tại có cho thấy đang mưa không: mã điều kiện thuộc nhóm
  /// dông (2xx) / mưa phùn (3xx) / mưa (5xx), hoặc lượng mưa 1h gần nhất đủ
  /// lớn. Quan trắc quá cũ so với [ref] thì bỏ qua (không đại diện "bây giờ").
  bool _obsIndicatesRain(CurrentWeather current, DateTime ref) {
    final age = ref.difference(current.time);
    if (age > const Duration(minutes: AppConfig.rainObsMaxAgeMinutes)) {
      return false;
    }
    final id = current.conditionId;
    final rainCondition = (id >= 200 && id < 400) || (id >= 500 && id < 600);
    return rainCondition || current.rain1h >= AppConfig.rainObsMm1hThreshold;
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

  // --- Tiêu chí "ướt" cho một giờ hourly ---

  /// Giờ được coi là ướt: có lượng mưa dự báo hoặc xác suất đủ cao.
  bool _isWetHour(HourlyForecast h) =>
      h.rainMm > _threshold || h.pop >= _popThreshold;

  /// Giờ "chắc chắn mưa" — dùng khi hourly MÂU THUẪN với nowcast (nowcast bảo
  /// khô): cần cả lượng mưa cụ thể lẫn pop cao để không báo nhầm cả ngày mùa
  /// mưa chỉ vì pop suông.
  bool _isConfidentWetHour(HourlyForecast h) =>
      h.rainMm > _threshold && h.pop >= AppConfig.rainConfidentPopThreshold;

  // --- Phân tích theo chuỗi dự báo ngắn hạn ---
  //
  // Độc lập với độ phân giải: dùng MỐC THỜI GIAN (time) so với [ref], nên
  // chạy đúng cho cả `minutely` 1 phút (One Call 3.0) lẫn nowcast 15 phút
  // (One Call 4.0 — đã chuẩn hoá về cùng entity ở data layer).
  RainStatus _fromMinutely(
    List<MinutelyForecast> minutely,
    List<HourlyForecast> hourly,
    DateTime ref,
  ) {
    final rainingNow = minutely.first.precipitationMmH > _threshold;

    if (!rainingNow) {
      // Đang khô → tìm mốc đầu tiên có mưa trong nowcast.
      for (var i = 1; i < minutely.length; i++) {
        if (minutely[i].precipitationMmH > _threshold) {
          return _onsetFromMinutely(minutely, hourly, i, ref);
        }
      }
      // Nowcast khô suốt cửa sổ — nhưng nowcast hay BỎ SÓT mưa, nên vẫn đối
      // chiếu hourly để không mất cảnh báo sớm (đây từng là lý do app im lặng
      // tới khi trời đã mưa).
      return _onsetFromHourlyBeyondNowcast(minutely, hourly, ref);
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

  /// Dựng trạng thái "sắp mưa" khi nowcast thấy mưa tại mốc [onsetIndex]:
  /// giờ bắt đầu chính xác phút từ nowcast; giờ tạnh + diễn biến lấy từ
  /// nowcast nếu cơn mưa gói gọn trong cửa sổ, ngược lại nối tiếp bằng hourly.
  RainStatus _onsetFromMinutely(
    List<MinutelyForecast> minutely,
    List<HourlyForecast> hourly,
    int onsetIndex,
    DateTime ref,
  ) {
    final changeAt = minutely[onsetIndex].time;
    final minutelyEnd = _minutelyRainEnd(minutely, onsetIndex);

    List<RainSegment> segments;
    DateTime? endsAt = minutelyEnd;
    if (minutelyEnd != null) {
      // Cơn mưa nằm trọn trong cửa sổ nowcast → 1 đoạn, mốc chính xác phút.
      segments = [
        RainSegment(
          start: changeAt,
          end: minutelyEnd,
          intensity: _intensityOfMmH(_maxMinutelyRate(minutely, onsetIndex)),
        ),
      ];
    } else {
      // Mưa kéo dài quá cửa sổ nowcast → nối tiếp bằng hourly để vẫn trả lời
      // được "kéo dài đến bao giờ / diễn biến ra sao".
      final idx = _hourIndexContaining(hourly, changeAt);
      segments = idx != null
          ? _hourlySegments(hourly, idx, startAt: changeAt)
          : const <RainSegment>[];
      if (segments.isEmpty) {
        segments = [
          RainSegment(
            start: changeAt,
            intensity: _intensityOfMmH(_maxMinutelyRate(minutely, onsetIndex)),
          ),
        ];
      }
      endsAt = segments.last.end;
    }

    return RainStatus(
      phase: RainPhase.rainStartingSoon,
      changeAt: changeAt,
      minutesUntilChange: _minutesFrom(ref, changeAt),
      rainEndsAt: endsAt,
      segments: segments,
      fromMinutely: true,
    );
  }

  /// Nowcast bảo khô suốt cửa sổ → tìm onset trong hourly:
  /// - giờ nằm NGOÀI cửa sổ nowcast: tiêu chí ướt bình thường;
  /// - giờ nằm TRONG cửa sổ (mâu thuẫn nowcast): chỉ nhận tín hiệu mạnh
  ///   (mm thật + pop cao) và onset sớm nhất là ngay sau cửa sổ khô.
  RainStatus _onsetFromHourlyBeyondNowcast(
    List<MinutelyForecast> minutely,
    List<HourlyForecast> hourly,
    DateTime ref,
  ) {
    if (hourly.isEmpty) return const RainStatus.dry();
    final windowEnd = minutely.last.time.add(_minutelySlot);

    for (var i = 0; i < hourly.length; i++) {
      final h = hourly[i];
      final blockEnd = h.time.add(const Duration(hours: 1));
      final insideNowcast = h.time.isBefore(windowEnd);
      final wet = insideNowcast ? _isConfidentWetHour(h) : _isWetHour(h);
      if (!wet) continue;
      // Giờ ướt nằm GỌN trong cửa sổ nowcast đã khẳng định khô → nowcast thắng.
      if (insideNowcast && !blockEnd.isAfter(windowEnd)) continue;

      var at = h.time;
      if (insideNowcast && windowEnd.isAfter(at)) at = windowEnd;
      if (at.isBefore(ref)) at = ref;
      final minutes = _minutesFrom(ref, at);
      // Onset quá xa → chưa coi là "sắp mưa" (tránh báo quá sớm).
      if (minutes > AppConfig.rainSoonHorizonMinutes) {
        return const RainStatus.dry();
      }
      final segments = _hourlySegments(hourly, i, startAt: at);
      return RainStatus(
        phase: RainPhase.rainStartingSoon,
        changeAt: at,
        minutesUntilChange: minutes,
        rainEndsAt: segments.isNotEmpty ? segments.last.end : null,
        segments: segments,
        fromMinutely: false,
      );
    }
    return const RainStatus.dry();
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

  /// Lượng mưa lớn nhất (mm/h) trong phần còn lại của nowcast từ [from] — dùng
  /// phân cường độ cho đoạn mưa suy từ minutely (cửa sổ ngắn nên quét hết).
  double _maxMinutelyRate(List<MinutelyForecast> minutely, int from) {
    var max = 0.0;
    for (var i = from; i < minutely.length; i++) {
      if (minutely[i].precipitationMmH > max) max = minutely[i].precipitationMmH;
    }
    return max;
  }

  // --- Fallback theo giờ ---
  RainStatus _fromHourly(List<HourlyForecast> hourly, DateTime ref) {
    if (hourly.isEmpty) return const RainStatus.dry(fromMinutely: false);

    // Giờ đầu chỉ đại diện "bây giờ" nếu khối giờ của nó đang chứa ref.
    final rainingNow =
        !hourly.first.time.isAfter(ref) && _isWetHour(hourly.first);

    if (!rainingNow) {
      for (var i = 0; i < hourly.length; i++) {
        if (_isWetHour(hourly[i])) {
          final minutes = _minutesFrom(ref, hourly[i].time);
          // Onset quá xa → chưa coi là "sắp mưa" (tránh báo quá sớm).
          if (minutes > AppConfig.rainSoonHorizonMinutes) {
            return const RainStatus.dry(fromMinutely: false);
          }
          final segments = _hourlySegments(hourly, i);
          return RainStatus(
            phase: RainPhase.rainStartingSoon,
            changeAt: hourly[i].time,
            minutesUntilChange: minutes,
            // Giờ "khô" đầu tiên sau đợt mưa = thời điểm dự kiến tạnh.
            rainEndsAt: segments.isNotEmpty ? segments.last.end : null,
            segments: segments,
            fromMinutely: false,
          );
        }
      }
      return const RainStatus.dry(fromMinutely: false);
    }

    for (var i = 1; i < hourly.length; i++) {
      if (!_isWetHour(hourly[i])) {
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

  // --- Diễn biến theo đoạn cường độ (từ hourly) ---

  /// Index của giờ có khối [time, time+1h) chứa [at]; null nếu không có.
  int? _hourIndexContaining(List<HourlyForecast> hourly, DateTime at) {
    for (var i = 0; i < hourly.length; i++) {
      final end = hourly[i].time.add(const Duration(hours: 1));
      if (!at.isBefore(hourly[i].time) && at.isBefore(end)) return i;
    }
    return null;
  }

  /// Gom chuỗi giờ ướt LIỀN KỀ bắt đầu từ [fromIndex] thành các đoạn theo
  /// cường độ (đổi cường độ → đoạn mới). Đoạn đầu bắt đầu tại [startAt] (mốc
  /// onset chính xác) nếu có. Đoạn cuối end == null nếu chuỗi ướt chạy tới hết
  /// dữ liệu (không khẳng định được giờ tạnh) — giữ đúng ngữ nghĩa rainEndsAt.
  List<RainSegment> _hourlySegments(
    List<HourlyForecast> hourly,
    int fromIndex, {
    DateTime? startAt,
  }) {
    if (fromIndex < 0 || fromIndex >= hourly.length) return const [];
    if (!_isWetHour(hourly[fromIndex])) return const [];

    final segs = <_SegBuilder>[];
    var i = fromIndex;
    var brokeByGap = false;
    while (i < hourly.length && _isWetHour(hourly[i])) {
      // Chuỗi phải liền kề về thời gian; dữ liệu đứt quãng → khép chuỗi.
      if (i > fromIndex &&
          hourly[i].time !=
              hourly[i - 1].time.add(const Duration(hours: 1))) {
        brokeByGap = true;
        break;
      }
      final intensity = _intensityOfHour(hourly[i]);
      final pop = (hourly[i].pop * 100).round();
      final blockEnd = hourly[i].time.add(const Duration(hours: 1));
      if (segs.isNotEmpty && segs.last.intensity == intensity) {
        segs.last
          ..end = blockEnd
          ..maxPop = math.max(segs.last.maxPop, pop);
      } else {
        segs.add(_SegBuilder(
          start: segs.isEmpty ? (startAt ?? hourly[i].time) : hourly[i].time,
          end: blockEnd,
          intensity: intensity,
          maxPop: pop,
        ));
      }
      i++;
    }
    if (segs.isEmpty) return const [];
    // Ướt tới hết dữ liệu (không phải dừng vì gặp giờ khô/đứt quãng) → không
    // khẳng định giờ tạnh.
    if (!brokeByGap && i >= hourly.length) segs.last.end = null;

    return [
      for (final s in segs)
        RainSegment(
          start: s.start,
          end: s.end,
          intensity: s.intensity,
          maxPopPct: s.maxPop,
        ),
    ];
  }

  /// Cường độ theo lượng mưa dự báo của giờ; giờ chỉ có pop cao (không mm)
  /// → `possible` (thông tin "có thể mưa", để câu chữ nói mềm hơn).
  RainIntensity _intensityOfHour(HourlyForecast h) => _intensityOfMmH(h.rainMm);

  RainIntensity _intensityOfMmH(double mmH) {
    if (mmH >= WeatherCondition.kRainMmHSevere) return RainIntensity.heavy;
    if (mmH >= WeatherCondition.kRainMmHHeavy) return RainIntensity.moderate;
    if (mmH > _threshold) return RainIntensity.light;
    return RainIntensity.possible;
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

/// Builder tạm khi gom đoạn (RainSegment bất biến).
class _SegBuilder {
  DateTime start;
  DateTime? end;
  RainIntensity intensity;
  int maxPop;
  _SegBuilder({
    required this.start,
    required this.end,
    required this.intensity,
    required this.maxPop,
  });
}
