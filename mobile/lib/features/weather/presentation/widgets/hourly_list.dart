import 'package:flutter/material.dart';

import '../../domain/entities/hourly.dart';
import '../../domain/entities/minutely.dart';
import '../../domain/entities/weather_condition.dart';

/// Danh sách dự báo theo giờ (cuộn ngang): tình hình (emoji) + nhiệt độ + xác
/// suất mưa + lượng mưa dự báo.
///
/// Xác suất (%) là giá trị **LỚN HƠN** giữa **nowcast 15'** (nhạy hơn với mưa
/// sắp tới) và `hourly.pop`; giờ xa ngoài tầm nowcast chỉ còn `hourly.pop`.
/// Xem [effectiveHourPop]. Kèm ghi chú nhắc pop là ước tính của OpenWeatherMap —
/// mưa dông chiều vùng nhiệt đới có thể không được phản ánh đầy đủ.
class HourlyList extends StatelessWidget {
  final List<HourlyForecast> hourly;

  /// Nowcast 15' (nguồn pop nhạy hơn cho giờ gần). Có thể rỗng.
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
    final popPct = (effectiveHourPop(h, minutely) * 100).round();
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
}

/// pop hiển thị: **giá trị LỚN HƠN** giữa nowcast 15' (max các mốc trong khối
/// giờ) và `hourly.pop`. Giờ xa (ngoài tầm nowcast ~12h) tự động chỉ còn
/// `hourly.pop`.
///
/// ⚠️ Bản trước ƯU TIÊN nowcast, tức nowcast có dữ liệu là **thay thế hẳn**
/// `hourly.pop`. Lý do ban đầu đúng (nowcast nhạy hơn với mưa sắp tới, quan sát
/// thực tế 11/08/2026: giờ 18:00 hourly báo 0% trong khi nowcast báo 17%),
/// nhưng nó bất đối xứng: chiều ngược lại — nowcast thấp hơn hourly — app sẽ
/// hiện số THẤP HƠN chính dự báo của OWM, tức tự bịt mắt mình đúng cái chiều đã
/// gây ra vụ 10/08 (app im lặng trong khi trời đang mưa).
///
/// Lấy `max` giữ nguyên ích lợi của nowcast mà bỏ được rủi ro đó: app không bao
/// giờ hiện khả năng mưa thấp hơn con số OWM đưa ra ở bất kỳ nguồn nào.
/// (Đo thực tế Manila + TP.HCM ngày 11/08: 0 giờ nào nowcast < hourly, nên đây
/// là gia cố phòng xa chứ không sửa một lỗi đang xảy ra.)
double effectiveHourPop(HourlyForecast h, List<MinutelyForecast> minutely) {
  final blockEnd = h.time.add(const Duration(hours: 1));
  var best = h.pop;
  for (final m in minutely) {
    if (!m.time.isBefore(h.time) && m.time.isBefore(blockEnd)) {
      if (m.pop > best) best = m.pop;
    }
  }
  return best;
}
