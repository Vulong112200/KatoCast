import 'package:katocast/features/weather/domain/entities/hourly.dart';
import 'package:katocast/features/weather/domain/entities/minutely.dart';
import 'package:katocast/features/weather/domain/entities/weather.dart';

/// Fixtures dữ liệu giả để test toàn bộ logic thời tiết một cách TẤT ĐỊNH.
///
/// Mọi builder neo thời gian vào [now] truyền vào (không dùng DateTime.now()),
/// nên các usecase (nhận `now`) test được ổn định. Dùng chung cho các test:
/// AnalyzeRain, BuildDailyDigest, BuildAdvisories, BuildRainOutlook,
/// BuildWeatherAlerts, DetectEnvChange.

/// Mốc "bây giờ" chuẩn cho test (trưa 25/06/2026).
final fakeNow = DateTime(2026, 6, 25, 12);

CurrentWeather fakeCurrent({
  DateTime? time,
  double tempC = 30,
  double feelsLikeC = 32,
  int humidity = 70,
  double uvi = 5,
  int clouds = 40,
  double windSpeed = 2,
  int conditionId = 803, // nhiều mây
  String description = 'nhiều mây',
  String icon = '03d',
  double rain1h = 0,
}) {
  return CurrentWeather(
    time: time ?? fakeNow,
    tempC: tempC,
    feelsLikeC: feelsLikeC,
    humidity: humidity,
    uvi: uvi,
    clouds: clouds,
    windSpeed: windSpeed,
    conditionId: conditionId,
    description: description,
    icon: icon,
    rain1h: rain1h,
  );
}

/// Chuỗi hourly bắt đầu từ đầu giờ của [start], [count] giờ liên tiếp.
/// [popAt]/[rainAt]/[tempAt]/[humidityAt] nhận index giờ (0..count-1).
List<HourlyForecast> fakeHourly({
  required DateTime start,
  int count = 12,
  double Function(int i)? popAt,
  double Function(int i)? rainAt,
  double Function(int i)? tempAt,
  int Function(int i)? humidityAt,
}) {
  final base = DateTime(start.year, start.month, start.day, start.hour);
  return [
    for (var i = 0; i < count; i++)
      HourlyForecast(
        time: base.add(Duration(hours: i)),
        tempC: tempAt?.call(i) ?? 30,
        humidity: humidityAt?.call(i) ?? 70,
        pop: popAt?.call(i) ?? 0,
        rainMm: rainAt?.call(i) ?? 0,
        description: '',
        icon: '',
      ),
  ];
}

/// Chuỗi minutely từ [start], mỗi phần tử cách nhau [stepMinutes] phút.
List<MinutelyForecast> fakeMinutely(
  List<double> values, {
  required DateTime start,
  int stepMinutes = 1,
}) {
  return [
    for (var i = 0; i < values.length; i++)
      MinutelyForecast(
        time: start.add(Duration(minutes: i * stepMinutes)),
        precipitationMmH: values[i],
      ),
  ];
}

WeatherData fakeWeather({
  CurrentWeather? current,
  List<MinutelyForecast> minutely = const [],
  List<HourlyForecast> hourly = const [],
  DateTime? fetchedAt,
}) {
  return WeatherData(
    current: current ?? fakeCurrent(),
    minutely: minutely,
    hourly: hourly,
    fetchedAt: fetchedAt ?? fakeNow,
  );
}

// --- Kịch bản dựng sẵn (WeatherData đầy đủ) ---

/// Quang mây, khô ráo cả ngày.
WeatherData clearScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, conditionId: 800, uvi: 2, humidity: 55),
    hourly: fakeHourly(start: t, count: 12),
  );
}

/// Đang mưa (minutely dày đặc mưa) + hourly xác nhận.
WeatherData rainingNowScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, conditionId: 501, rain1h: 3),
    minutely: fakeMinutely(List<double>.filled(60, 2.5), start: t),
    hourly: fakeHourly(start: t, count: 6, popAt: (i) => 0.9, rainAt: (i) => 2),
  );
}

/// Khô nhưng sắp mưa sau 20 phút, kéo dài ~10 phút.
WeatherData rainSoonScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  final vals = List<double>.filled(60, 0.0);
  for (var i = 20; i < 30; i++) {
    vals[i] = 1.8;
  }
  return fakeWeather(
    current: fakeCurrent(time: t),
    minutely: fakeMinutely(vals, start: t),
    hourly: fakeHourly(start: t, count: 6, popAt: (i) => i == 0 ? 0.7 : 0.9),
  );
}

/// Dông/bão lớn.
WeatherData stormScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, conditionId: 212, rain1h: 8, windSpeed: 14),
    minutely: fakeMinutely(List<double>.filled(60, 6), start: t),
    hourly: fakeHourly(start: t, count: 6, popAt: (i) => 1.0, rainAt: (i) => 6),
  );
}

/// UV cực cao (nắng gắt).
WeatherData highUvScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, conditionId: 800, uvi: 11, humidity: 45),
    hourly: fakeHourly(start: t, count: 12),
  );
}

/// Độ ẩm cao + gió mạnh (để test advisory ẩm/gió).
WeatherData humidWindyScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, humidity: 88, windSpeed: 12, uvi: 2),
    hourly: fakeHourly(start: t, count: 12),
  );
}

/// Thay đổi môi trường mạnh: nhiệt độ tăng vọt trong 3h tới.
WeatherData envChangeScenario({DateTime? now}) {
  final t = now ?? fakeNow;
  return fakeWeather(
    current: fakeCurrent(time: t, tempC: 25, humidity: 60),
    hourly: fakeHourly(
      start: t,
      count: 6,
      tempAt: (i) => 25 + i * 3.0, // +9°C ở giờ thứ 3
    ),
  );
}
