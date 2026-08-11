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
    //
    // [nowcastSawNoRainAtAll] chặn ca NGƯỢC LẠI: mưa VỪA TẠNH, `rain1h` còn dư
    // — xem [_obsIndicatesRain].
    // ⚠️ Nowcast chỉ được quyền PHỦ QUYẾT quan trắc khi nó THẬT SỰ nói khô trên
    // TOÀN cửa sổ. Bản cũ suy cờ này từ `base.phase == RainPhase.dry` — một phép
    // xấp xỉ SAI: pha vẫn ra `dry` khi mốc hiện tại có mưa nhẹ 0.1–0.49 mm/h
    // (chưa đủ tuyên bố "đang mưa", mà vòng tìm onset lại bỏ qua mốc hiện tại).
    // Khi đó nowcast ĐANG THẤY MƯA nhưng vẫn phủ quyết quan trắc — đúng chiều
    // gây im lặng. Nay quét thật cả cửa sổ; điều kiện `phase == dry` giữ nguyên
    // để không mất carve-out "nowcast thấy mưa sắp tới thì đừng phủ quyết".
    final nowcastDeniesRain =
        minutely.isNotEmpty &&
        base.phase == RainPhase.dry &&
        minutely.every((m) => m.precipitationMmH <= _threshold);

    if (!base.isRainingNow &&
        _obsIndicatesRain(
          data.current,
          ref,
          nowcastSawNoRainAtAll: nowcastDeniesRain,
        )) {
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
      // Chỉ ép sàn xác suất khi ĐANG mưa thực sự (quan trắc/nowcast xác nhận) —
      // lúc đó "khả năng 30%" là vô lý. Với "sắp mưa" thì hiện pop THẬT của OWM
      // để không thổi phồng con số (trước đây ép ≥80% cả khi mới sắp mưa).
      floorProbability: base.phase == RainPhase.raining,
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

  /// Quan trắc hiện tại có cho thấy đang mưa không.
  ///
  /// ⚠️ KHÔNG tin `conditionId` một mình cho các mã YẾU/VỪA. OpenWeatherMap gán
  /// rất thoáng mã 500 ("light rain") và nhóm 3xx ("drizzle") cho trời chỉ âm u/
  /// ẩm cao, và GIỮ NGUYÊN mã mưa gần một tiếng sau khi cơn mưa đã tạnh — nhật ký
  /// thật cho thấy app tuyên bố "Trời đang mưa" trong khi ngoài trời không mưa.
  /// Nên:
  /// - mã KHÔNG THỂ NHẦM (dông 2xx, mưa TO trở lên 502+) → tin ngay;
  /// - mã còn lại của nhóm mưa/mưa phùn (3xx, 500 light, **501 moderate**) → chỉ
  ///   tin khi có **bằng chứng lượng mưa thật** (`rain1h`) và nowcast không phủ
  ///   định sạch cửa sổ.
  /// Quan trắc quá cũ so với [ref] thì bỏ qua (không đại diện "bây giờ").
  ///
  /// [nowcastSawNoRainAtAll] = nowcast có dữ liệu và KHÔNG thấy mưa ở bất kỳ
  /// đâu trong cửa sổ của nó (kết luận `dry`, không phải "sắp mưa"). Đây là cái
  /// van chặn ca MƯA VỪA TẠNH:
  ///
  /// `current.rain1h` là lượng mưa **TÍCH LŨY của một giờ vừa qua**, KHÔNG phải
  /// cường độ lúc này. Mưa tạnh rồi nó vẫn > 0 suốt gần một tiếng, và OWM còn
  /// giữ nguyên mã 500 kèm theo. Bản cũ chỉ cần `rain1h >= 0.5` là tuyên bố
  /// "đang mưa" bất kể nowcast → nhật ký thật 01/08/2026 12:32–12:55:
  /// `nowcast bây giờ 0.00 mm/h · mưa 1h quan trắc 0.74 mm · mã OWM 500` mà app
  /// vẫn báo "Trời đang mưa · khả năng còn mưa 80%" (80% do sàn xác suất chỉ áp
  /// khi ĐANG mưa). Hậu quả nặng hơn cả câu sai: pha KẸT ở `raining` nên
  /// `rainStartingSoon` không bao giờ tới và app im lặng hoàn toàn — nhật ký lặp
  /// lại "KHÔNG báo — pha trước raining, pha nay raining" hàng chục phút liền.
  ///
  /// Van này cố ý HẸP để không làm sống lại lỗi ngược (nowcast VN hay bỏ sót
  /// mưa → app im lặng khi trời đã mưa thật). Nó KHÔNG chặn:
  /// - mã KHÔNG THỂ NHẦM (dông 2xx, mưa TO trở lên 502+): nowcast sai thì nowcast
  ///   chịu;
  /// - lượng mưa quan trắc LỚN ([AppConfig.rainObsHeavyMm1hThreshold]);
  /// - khi nowcast thấy mưa sắp tới (nowcast chỉ TRỄ, không phải phủ định).
  ///
  /// ⚠️ **501 ("mưa vừa") ĐÃ BỊ ĐƯA RA khỏi nhóm "tin ngay"** (bản trước gộp
  /// `501+` vào đó). Nhật ký thật 06/08/2026 cho thấy mã 501 lag y như 500:
  /// 12:38 → 13:54 liên tục `nowcast bây giờ 0.00 mm/h · mưa 1h quan trắc
  /// 1.55→1.14 mm · mã OWM 501`, app báo "Trời đang mưa · còn mưa 100%" rồi KẸT
  /// pha `raining` suốt 1 giờ 16 phút ("KHÔNG báo — pha trước raining, pha nay
  /// raining" ở cả 3 lớp nền). Đó đúng là hậu quả nặng nhất mà cái van này được
  /// tạo ra để chặn, chỉ khác con số mã. Lý do 501 an toàn khi bỏ ra: mưa vừa
  /// THẬT (2.5–7.6 mm/h) thì `rain1h` vượt 2 mm rất nhanh và lọt qua van bằng
  /// [AppConfig.rainObsHeavyMm1hThreshold]; còn 501 kèm `rain1h` nhỏ dần đúng là
  /// dấu vết của cơn mưa VỪA TẠNH.
  bool _obsIndicatesRain(
    CurrentWeather current,
    DateTime ref, {
    bool nowcastSawNoRainAtAll = false,
  }) {
    final age = ref.difference(current.time);
    if (age > const Duration(minutes: AppConfig.rainObsMaxAgeMinutes)) {
      return false;
    }

    final id = current.conditionId;
    // Dông (2xx) hoặc mưa TO trở lên (502+) — mã không thể nhầm với trời âm u,
    // cũng không thể là "dư" của một cơn mưa nhỏ vừa tạnh.
    final unmistakableRainCode =
        id != null && ((id >= 200 && id < 300) || (id >= 502 && id < 600));
    if (unmistakableRainCode) return true;

    // Mưa quan trắc RẤT nhiều → đang mưa thật, không thể là dư của cơn đã tạnh.
    if (current.rain1h >= AppConfig.rainObsHeavyMm1hThreshold) return true;

    // Từ đây bằng chứng chỉ ở mức YẾU/VỪA (mã 3xx/500/501, hoặc chỉ có `rain1h`
    // vừa phải). Nowcast phủ định sạch cả cửa sổ → tin nowcast: mưa đã tạnh.
    if (nowcastSawNoRainAtAll) return false;

    // Lượng mưa quan trắc đủ lớn → coi là đang mưa, bất kể mã điều kiện.
    if (current.rain1h >= AppConfig.rainObsMm1hThreshold) return true;

    if (id == null) return false;
    // Mã 3xx (drizzle) / 500 (light) / 501 (moderate) → cần lượng mưa đo được.
    final rainCodeNeedingProof =
        (id >= 300 && id < 400) || id == 500 || id == 501;
    return rainCodeNeedingProof && current.rain1h > 0;
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

  /// Nowcast có khẳng định **ĐANG mưa ngay lúc này** không?
  ///
  /// Đây là quyết định dễ sai nhất trong toàn bộ logic mưa, nên nó có tiêu chí
  /// RIÊNG, chặt hơn tiêu chí "sắp mưa":
  /// - mưa rõ ràng ([AppConfig.rainNowObviousMmH]) → tuyên bố ngay;
  /// - còn lại phải đạt [AppConfig.rainNowThresholdMmH] và **duy trì** qua
  ///   [AppConfig.rainNowSustainedSlots] mốc liên tiếp.
  ///
  /// Nếu chỉ dùng một ngưỡng thấp cho một mốc đơn lẻ (bản cũ: `> 0.1` tại
  /// `minutely.first`) thì mưa VẾT lúc trời âm u cũng bật pha `raining`, và vì
  /// pha chỉ đổi khi giá trị khác đi, app sẽ KẸT ở "đang mưa" nhiều giờ: không
  /// còn cảnh báo "sắp mưa", cũng không còn thông báo nào cả.
  ///
  /// ⚠️ Khoảng `(rainThresholdMmH, rainNowThresholdMmH)` = 0.1–0.49 mm/h từng là
  /// một **VÙNG CHẾT**: quá yếu để gọi "đang mưa", nhưng đủ để mốc kế tiếp bị gán
  /// "sắp mưa", nên mỗi chu kỳ mốc onset lại trượt về sau, pha đứng yên ở
  /// `rainStartingSoon` và `phaseChanged` không bao giờ true ⇒ app im lặng trong
  /// khi ngoài trời đang mưa nhẹ. Nay vùng chết KHÔNG THỂ XẢY RA từ nowcast: mọi
  /// giá trị `minutely` được suy từ `weather[].id` (xem
  /// `WeatherRemoteDataSource._precipFromCondition`) và bảng ánh xạ cố ý không có
  /// mức nào rơi vào 0.1–0.49 — mỗi mốc hoặc 0.0, hoặc ≥ 0.5. Giữ ngưỡng 0.5 ở
  /// đây vì nó vẫn cần cho `_fromHourly` (mm THẬT, có thể là 0.2) và vì nó là
  /// lưới chống báo nhầm đã được tinh chỉnh qua nhiều vòng.
  bool _nowcastSaysRainingNow(List<MinutelyForecast> minutely) {
    final now = minutely.first.precipitationMmH;
    if (now >= AppConfig.rainNowObviousMmH) return true;
    if (now < AppConfig.rainNowThresholdMmH) return false;

    final need = AppConfig.rainNowSustainedSlots;
    // Dữ liệu ngắn hơn số mốc cần → xét hết những gì có.
    final end = need < minutely.length ? need : minutely.length;
    for (var i = 0; i < end; i++) {
      if (minutely[i].precipitationMmH < AppConfig.rainNowThresholdMmH) {
        return false;
      }
    }
    return true;
  }

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
    final rainingNow = _nowcastSaysRainingNow(minutely);

    if (!rainingNow) {
      // Đang khô, HOẶC mốc hiện tại chỉ có mưa VẾT chưa đáng gọi là mưa → nhìn
      // về phía TRƯỚC tìm mốc mưa đầu tiên. Quét từ mốc 1 (không lấy mốc hiện
      // tại làm onset: "dự kiến mưa ngay bây giờ" vừa vô nghĩa vừa đúng là câu
      // gây nhầm mà người dùng phản ánh); nhờ vậy trời âm u có mưa vết bây giờ mà
      // mưa thật đến sau 45' sẽ ra đúng "Sắp mưa lúc HH:MM".
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
    final endIndex = _minutelyRainEndIndex(minutely, onsetIndex);
    final minutelyEnd = endIndex != null ? minutely[endIndex].time : null;

    List<RainSegment> segments;
    DateTime? endsAt = minutelyEnd;
    if (endIndex != null) {
      // Cơn mưa nằm trọn trong cửa sổ nowcast → 1 đoạn, mốc chính xác phút.
      // Chỉ quét cường độ trong [onsetIndex, endIndex) để một cơn mưa KHÁC ở
      // cuối cửa sổ không thổi phồng cường độ đoạn này.
      segments = [
        RainSegment(
          start: changeAt,
          end: minutelyEnd,
          intensity: _intensityOfMmH(
            _maxMinutelyRate(minutely, onsetIndex, to: endIndex),
          ),
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

  /// Từ mốc bắt đầu mưa [rainStart], quét tiếp tìm CHỈ SỐ mốc "khô bền vững"
  /// đầu tiên → thời điểm cơn mưa tạnh. null nếu tới hết cửa sổ vẫn còn mưa (cơn
  /// mưa kéo dài quá tầm dự báo ngắn — không khẳng định được giờ tạnh).
  int? _minutelyRainEndIndex(List<MinutelyForecast> minutely, int rainStart) {
    for (var i = rainStart + 1; i < minutely.length; i++) {
      if (minutely[i].precipitationMmH <= _threshold &&
          _isDrySustained(minutely, i)) {
        return i;
      }
    }
    return null;
  }

  /// Lượng mưa lớn nhất (mm/h) trong khoảng [from, to) của nowcast — dùng phân
  /// cường độ cho đoạn mưa suy từ minutely. [to] mặc định hết chuỗi; truyền chỉ
  /// số kết thúc cơn mưa để KHÔNG tính lẫn cơn mưa khác ở phần sau cửa sổ.
  double _maxMinutelyRate(
    List<MinutelyForecast> minutely,
    int from, {
    int? to,
  }) {
    final end = to ?? minutely.length;
    var max = 0.0;
    for (var i = from; i < end; i++) {
      if (minutely[i].precipitationMmH > max) {
        max = minutely[i].precipitationMmH;
      }
    }
    return max;
  }

  // --- Fallback theo giờ ---
  RainStatus _fromHourly(List<HourlyForecast> hourly, DateTime ref) {
    if (hourly.isEmpty) return const RainStatus.dry(fromMinutely: false);

    // Giờ đầu chỉ đại diện "bây giờ" nếu khối giờ của nó đang chứa ref.
    //
    // Tuyên bố "ĐANG mưa" ở đây phải dựa vào LƯỢNG MƯA dự báo, KHÔNG dùng
    // `_isWetHour` (vốn nhận cả `pop >= 50%`): "50% khả năng mưa trong giờ này"
    // không phải là "trời đang mưa". Đây là cùng loại lỗi với ngưỡng nowcast —
    // nó khiến pha kẹt ở `raining` và giết mọi cảnh báo "sắp mưa".
    final rainingNow =
        !hourly.first.time.isAfter(ref) &&
        hourly.first.rainMm >= AppConfig.rainNowThresholdMmH;

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
          hourly[i].time != hourly[i - 1].time.add(const Duration(hours: 1))) {
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
        segs.add(
          _SegBuilder(
            start: segs.isEmpty ? (startAt ?? hourly[i].time) : hourly[i].time,
            end: blockEnd,
            intensity: intensity,
            maxPop: pop,
          ),
        );
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
  /// [floorProbability] = ĐANG mưa → floor xác suất để không mâu thuẫn kiểu
  /// "đang mưa, khả năng 40%". Với "sắp mưa" thì KHÔNG floor → trả pop thật.
  /// null nếu không có nguồn nào.
  int? _probabilityPct(
    List<HourlyForecast> hourly, {
    required DateTime eventTime,
    required bool floorProbability,
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
    if (floorProbability) {
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
