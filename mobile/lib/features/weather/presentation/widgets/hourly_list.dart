import 'package:flutter/material.dart';

import '../../domain/entities/hourly.dart';
import '../../domain/entities/minutely.dart';
import '../../domain/entities/weather_condition.dart';

/// Danh sách dự báo theo giờ (cuộn ngang): tình hình (emoji) + nhiệt độ + xác
/// suất mưa + lượng mưa dự báo.
///
/// Xác suất (%) cho các giờ GẦN được lấy từ **nowcast 15'** (nhạy hơn với mưa
/// sắp tới) nếu có; các giờ xa dùng `hourly.pop`. Kèm ghi chú nhắc pop là ước
/// tính của OpenWeatherMap — mưa dông chiều vùng nhiệt đới có thể không được
/// phản ánh đầy đủ.
class HourlyList extends StatelessWidget {
  final List<HourlyForecast> hourly;

  /// Nowcast 15' (để ưu tiên pop nhạy hơn cho giờ gần). Có thể rỗng.
  final List<MinutelyForecast> minutely;

  const HourlyList({
    super.key,
    required this.hourly,
    this.minutely = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const SizedBox.shrink();
    final items = hourly.take(24).toList();
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _hourCard(context, items[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '% là ước tính của OpenWeatherMap; mưa dông chiều có thể không được '
            'phản ánh đầy đủ. Cảnh báo mưa của app còn dựa vào quan trắc & '
            'nowcast 15 phút.',
            style: t.bodySmall?.copyWith(
              color: t.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hourCard(BuildContext context, HourlyForecast h) {
    final t = Theme.of(context).textTheme;
    final popPct = (_effectivePop(h) * 100).round();
    final emoji =
        WeatherCondition.classify(h.conditionId, rainMmH: h.rainMm).emoji;
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${h.time.hour}:00', style: t.bodySmall),
          Text(emoji, style: const TextStyle(fontSize: 20)),
          Text('${h.tempC.round()}°', style: t.titleMedium),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.umbrella,
                  size: 14, color: popPct > 0 ? Colors.blue : Colors.grey),
              const SizedBox(width: 2),
              Text('$popPct%', style: t.bodySmall),
            ],
          ),
          // Lượng mưa dự báo (chỉ hiện khi có) — bổ sung cho pop hay bằng 0.
          Text(
            h.rainMm > 0 ? '${h.rainMm.toStringAsFixed(1)} mm' : '—',
            style: t.bodySmall?.copyWith(
              color: h.rainMm > 0
                  ? Colors.blue
                  : t.bodySmall?.color?.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// pop hiển thị: ưu tiên nowcast 15' (max các mốc trong khối giờ) nếu có, ngược
  /// lại dùng hourly.pop. Nowcast nhạy hơn với mưa sắp tới nên giờ gần chính xác
  /// hơn; giờ xa (ngoài tầm nowcast ~12h) tự động rơi về hourly.pop.
  double _effectivePop(HourlyForecast h) {
    final blockEnd = h.time.add(const Duration(hours: 1));
    double? maxNow;
    for (final m in minutely) {
      if (!m.time.isBefore(h.time) && m.time.isBefore(blockEnd)) {
        maxNow = maxNow == null ? m.pop : (m.pop > maxNow ? m.pop : maxNow);
      }
    }
    return maxNow ?? h.pop;
  }
}
