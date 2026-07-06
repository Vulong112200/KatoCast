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
    final uv = UvAdvice.classify(current.uvi);
    final hiLo = _hiLo();
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${current.tempC.round()}°C',
                style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              '${current.description} · cảm giác ${current.feelsLikeC.round()}°C',
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
                _metric(context, Icons.water_drop, 'Độ ẩm',
                    '${current.humidity}%'),
                _metric(context, Icons.wb_sunny, 'UV',
                    '${uv.level} · ${uv.label}', color: _uvColor(uv.band)),
                _metric(context, Icons.cloud, 'Mây', '${current.clouds}%'),
                _metric(context, Icons.umbrella, 'Mưa 1h',
                    '${current.rain1h.toStringAsFixed(1)} mm'),
                _metric(context, Icons.air, 'Gió',
                    '${current.windSpeed.toStringAsFixed(1)} m/s'),
              ],
            ),
          ],
        ),
      ),
    );
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
