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
        return (
          Colors.blue,
          Icons.umbrella,
          'Dự kiến mưa ${_timing()}.${_chance()} '
              'Chuẩn bị áo mưa và chú ý đường trơn trượt.',
        );
      case RainPhase.raining:
        return (
          Colors.indigo,
          Icons.water_drop,
          'Hiện đang có mưa tại vị trí của bạn.${_chance(raining: true)}',
        );
      case RainPhase.rainStoppingSoon:
        return (
          Colors.teal,
          Icons.wb_cloudy,
          'Mưa dự kiến tạnh ${_timing()}. Đường có thể còn ướt.',
        );
      case RainPhase.dry:
        return (Colors.green, Icons.wb_sunny, null);
    }
  }

  /// "lúc HH:MM (~N phút tới)" từ timestamp dự báo — khớp nội dung notification.
  String _timing() {
    final at = status.changeAt;
    final n = status.minutesUntilChange ?? 0;
    if (at == null) return n <= 0 ? 'ngay bây giờ' : 'trong ~$n phút tới';
    if (n <= 0) return 'ngay bây giờ';
    final clock = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return 'lúc $clock (~$n phút tới)';
  }

  String _chance({bool raining = false}) {
    final pct = status.probabilityPct;
    if (pct == null) return '';
    return raining ? ' Khả năng còn mưa ~$pct%.' : ' Khả năng mưa ~$pct%.';
  }
}
