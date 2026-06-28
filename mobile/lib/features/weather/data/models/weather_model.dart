import '../../domain/entities/hourly.dart';
import '../../domain/entities/minutely.dart';
import '../../domain/entities/weather.dart';

/// Mapper Data Layer: JSON One Call 3.0 → domain entities.
///
/// Dùng parser thủ công có guard null thay vì codegen vì payload của bên thứ ba
/// nhiều trường lồng nhau/optional (rain, minutely có thể vắng); parser tay
/// kiểm soát rõ ràng hơn và không sinh code thừa. Domain entity hoàn toàn
/// không biết gì về cấu trúc JSON này.
class WeatherMapper {
  const WeatherMapper._();

  static WeatherData fromOneCallJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    return WeatherData(
      current: _current(_asMap(json['current'])),
      minutely: _minutelyList(json['minutely']),
      hourly: _hourlyList(json['hourly']),
      fetchedAt: fetchedAt,
    );
  }

  static CurrentWeather _current(Map<String, dynamic> c) {
    final weather = _firstWeather(c['weather']);
    return CurrentWeather(
      time: _time(c['dt']),
      tempC: _toDouble(c['temp']),
      feelsLikeC: _toDouble(c['feels_like']),
      humidity: _toInt(c['humidity']),
      uvi: _toDouble(c['uvi']),
      clouds: _toInt(c['clouds']),
      windSpeed: _toDouble(c['wind_speed']),
      conditionId: weather.$1,
      description: weather.$2,
      icon: weather.$3,
      rain1h: _rainAmount(c['rain']),
    );
  }

  static List<MinutelyForecast> _minutelyList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      final m = _asMap(e);
      return MinutelyForecast(
        time: _time(m['dt']),
        precipitationMmH: _toDouble(m['precipitation']),
      );
    }).toList();
  }

  static List<HourlyForecast> _hourlyList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      final h = _asMap(e);
      final weather = _firstWeather(h['weather']);
      return HourlyForecast(
        time: _time(h['dt']),
        tempC: _toDouble(h['temp']),
        humidity: _toInt(h['humidity']),
        pop: _toDouble(h['pop']),
        rainMm: _rainAmount(h['rain']),
        description: weather.$2,
        icon: weather.$3,
      );
    }).toList();
  }

  // --- Helpers an toàn null ---

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static DateTime _time(dynamic dt) => DateTime.fromMillisecondsSinceEpoch(
        _toInt(dt) * 1000,
        isUtc: true,
      ).toLocal();

  static double _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  static int _toInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// rain có thể là {"1h": 0.5} (current) hoặc số (hourly đôi khi). Trả 0 nếu vắng.
  static double _rainAmount(dynamic rain) {
    if (rain is num) return rain.toDouble();
    if (rain is Map && rain['1h'] is num) return (rain['1h'] as num).toDouble();
    return 0.0;
  }

  /// (conditionId, description, icon) từ weather[0].
  static (int, String, String) _firstWeather(dynamic weather) {
    if (weather is List && weather.isNotEmpty) {
      final w = _asMap(weather.first);
      return (
        _toInt(w['id']),
        '${w['description'] ?? ''}',
        '${w['icon'] ?? ''}',
      );
    }
    // Thiếu weather[] → mặc định 800 (trời quang) thay vì 0 (mã không hợp lệ)
    // để tránh phân loại nhầm thành "Thời tiết / other".
    return (800, '', '');
  }
}
