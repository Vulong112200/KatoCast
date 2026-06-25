import 'package:flutter/material.dart';

import '../../domain/entities/weather_condition.dart';

/// Hiển thị tình hình thời tiết hiện tại (nắng/mây/mưa/bão) + lời khuyên.
/// Màu theo mức độ nghiêm trọng để người dùng nhận biết nhanh.
class ConditionCard extends StatelessWidget {
  final WeatherCondition condition;
  const ConditionCard({super.key, required this.condition});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(condition.severity);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(condition.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(condition.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                if (condition.advice.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(condition.advice,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(WeatherSeverity s) {
    switch (s) {
      case WeatherSeverity.info:
        return Colors.green;
      case WeatherSeverity.notice:
        return Colors.blue;
      case WeatherSeverity.warning:
        return Colors.orange;
      case WeatherSeverity.severe:
        return Colors.red;
    }
  }
}
