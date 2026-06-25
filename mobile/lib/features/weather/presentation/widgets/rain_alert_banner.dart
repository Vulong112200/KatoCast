import 'package:flutter/material.dart';

import '../../domain/entities/rain_status.dart';

/// Banner cảnh báo mưa hiển thị ngay trên màn hình (đồng bộ với notification).
class RainAlertBanner extends StatelessWidget {
  final RainStatus status;
  const RainAlertBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = _content();
    if (text == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String?) _content() {
    switch (status.phase) {
      case RainPhase.rainStartingSoon:
        final n = status.minutesUntilChange ?? 0;
        return (
          Colors.blue,
          Icons.umbrella,
          'Dự kiến mưa trong $n phút tới. Chuẩn bị áo mưa và chú ý đường trơn trượt.',
        );
      case RainPhase.raining:
        return (Colors.indigo, Icons.water_drop, 'Hiện đang có mưa tại vị trí của bạn.');
      case RainPhase.rainStoppingSoon:
        final n = status.minutesUntilChange ?? 0;
        return (
          Colors.teal,
          Icons.wb_cloudy,
          'Mưa dự kiến tạnh trong $n phút tới. Đường có thể còn ướt.',
        );
      case RainPhase.dry:
        return (Colors.green, Icons.wb_sunny, null);
    }
  }
}
