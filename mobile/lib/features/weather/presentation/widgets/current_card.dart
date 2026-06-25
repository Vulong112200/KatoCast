import 'package:flutter/material.dart';

import '../../domain/entities/weather.dart';

/// Thẻ thời tiết hiện tại: nhiệt độ, cảm giác, độ ẩm, UV, mưa.
class CurrentWeatherCard extends StatelessWidget {
  final CurrentWeather current;
  const CurrentWeatherCard({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _metric(context, Icons.water_drop, 'Độ ẩm', '${current.humidity}%'),
                _metric(context, Icons.wb_sunny, 'UV', current.uvi.toStringAsFixed(1)),
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

  Widget _metric(BuildContext context, IconData icon, String label, String value) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: t.titleMedium),
        Text(label, style: t.bodySmall),
      ],
    );
  }
}
