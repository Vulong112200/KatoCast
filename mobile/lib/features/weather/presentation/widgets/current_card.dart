import 'package:flutter/material.dart';

import '../../domain/entities/hourly.dart';
import '../../domain/entities/uv_advice.dart';
import '../../domain/entities/weather.dart';

/// Thẻ thời tiết hiện tại: nhiệt độ, cảm giác, hi/lo, độ ẩm, UV (kèm mức),
/// mây, mưa, gió.
class CurrentWeatherCard extends StatelessWidget {
  final CurrentWeather current;

  /// Dự báo giờ (để tính nhiệt độ cao/thấp trong ~24h tới). Có thể rỗng.
  final List<HourlyForecast> hourly;

  const CurrentWeatherCard({
    super.key,
    required this.current,
    this.hourly = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final uvi = current.uvi;
    final uv = uvi != null ? UvAdvice.classify(uvi) : null;
    final hiLo = _hiLo();
    final tempStr = current.tempC != null ? '${current.tempC!.round()}°C' : '—';
    final feelsStr =
        current.feelsLikeC != null ? '${current.feelsLikeC!.round()}°C' : '—';
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tempStr,
                style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              '${current.description} · cảm giác $feelsStr',
              style: t.bodyMedium,
            ),
            if (hiLo != null) ...[
              const SizedBox(height: 4),
              Text('Hôm nay ${hiLo.$1}° – ${hiLo.$2}°', style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _metric(context, Icons.water_drop, 'Độ ẩm', _pct(current.humidity)),
                _metric(context, Icons.wb_sunny, 'UV',
                    uv != null ? '${uv.level} · ${uv.label}' : '—',
                    color: uv != null ? _uvColor(uv.band) : null),
                _metric(context, Icons.cloud, 'Mây', _pct(current.clouds)),
                _metric(context, Icons.umbrella, 'Mưa 1h',
                    '${current.rain1h.toStringAsFixed(1)} mm'),
                _metric(context, Icons.air, 'Gió', _wind()),
                if (current.windGust != null)
                  _metric(context, Icons.storm, 'Gió giật',
                      '${current.windGust!.toStringAsFixed(1)} m/s'),
                if (current.dewPointC != null)
                  _metric(context, Icons.opacity, 'Điểm sương',
                      '${current.dewPointC!.round()}°C'),
                if (current.pressure != null)
                  _metric(context, Icons.speed, 'Áp suất',
                      '${current.pressure} hPa'),
                if (current.visibilityM != null)
                  _metric(context, Icons.visibility, 'Tầm nhìn',
                      _visibility(current.visibilityM!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "72%" hoặc "—" nếu thiếu.
  String _pct(int? v) => v != null ? '$v%' : '—';

  /// Gió: tốc độ (m/s) kèm hướng la bàn nếu có, "—" nếu thiếu tốc độ.
  String _wind() {
    final s = current.windSpeed;
    if (s == null) return '—';
    final dir = current.windDeg != null ? ' ${_compass(current.windDeg!)}' : '';
    return '${s.toStringAsFixed(1)} m/s$dir';
  }

  /// Tầm nhìn: km nếu ≥1000m, ngược lại theo mét.
  String _visibility(int m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';

  /// Độ (0–360) → hướng la bàn tiếng Việt (8 hướng).
  String _compass(int deg) {
    const dirs = ['B', 'ĐB', 'Đ', 'ĐN', 'N', 'TN', 'T', 'TB'];
    final i = (((deg % 360) + 22.5) ~/ 45) % 8;
    return dirs[i];
  }

  /// (thấp, cao) làm tròn trong ~24h tới, null nếu không có dữ liệu giờ.
  (int, int)? _hiLo() {
    final next24 = hourly.take(24).toList();
    if (next24.isEmpty) return null;
    var lo = next24.first.tempC;
    var hi = next24.first.tempC;
    for (final h in next24) {
      if (h.tempC < lo) lo = h.tempC;
      if (h.tempC > hi) hi = h.tempC;
    }
    return (lo.round(), hi.round());
  }

  Color? _uvColor(UvBand band) {
    switch (band) {
      case UvBand.low:
        return Colors.green;
      case UvBand.moderate:
        return Colors.lightGreen;
      case UvBand.high:
        return Colors.orange;
      case UvBand.veryHigh:
        return Colors.deepOrange;
      case UvBand.extreme:
        return Colors.purple;
    }
  }

  Widget _metric(BuildContext context, IconData icon, String label, String value,
      {Color? color}) {
    final t = Theme.of(context).textTheme;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: c),
        const SizedBox(height: 4),
        Text(value, style: t.titleMedium),
        Text(label, style: t.bodySmall),
      ],
    );
  }
}
