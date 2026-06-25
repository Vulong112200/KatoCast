import 'package:flutter/material.dart';

import '../../domain/entities/hourly.dart';

/// Danh sách dự báo theo giờ (cuộn ngang): nhiệt độ + xác suất mưa.
class HourlyList extends StatelessWidget {
  final List<HourlyForecast> hourly;
  const HourlyList({super.key, required this.hourly});

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const SizedBox.shrink();
    final items = hourly.take(24).toList();

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final h = items[i];
          final t = Theme.of(context).textTheme;
          return Container(
            width: 70,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${h.time.hour}:00', style: t.bodySmall),
                Text('${h.tempC.round()}°', style: t.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.umbrella, size: 14, color: Colors.blue),
                    const SizedBox(width: 2),
                    Text('${(h.pop * 100).round()}%', style: t.bodySmall),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
