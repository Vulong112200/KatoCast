import 'package:flutter/material.dart';

import '../../domain/usecases/build_advisories.dart';

/// Thẻ "Lưu ý hôm nay": danh sách các lời khuyên/lưu ý dễ hiểu (tình hình, UV,
/// độ ẩm, gió, mưa) từ `BuildAdvisories`. Ẩn nếu không có lưu ý nào.
class AdvisoryCard extends StatelessWidget {
  final List<Advisory> advisories;
  const AdvisoryCard({super.key, required this.advisories});

  @override
  Widget build(BuildContext context) {
    if (advisories.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🐾', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Kato mách bạn',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            for (final a in advisories) _row(context, a),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Advisory a) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(a.kind), size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(a.text, style: t.bodyMedium)),
        ],
      ),
    );
  }

  IconData _icon(AdvisoryKind kind) {
    switch (kind) {
      case AdvisoryKind.condition:
        return Icons.info_outline;
      case AdvisoryKind.uv:
        return Icons.wb_sunny_outlined;
      case AdvisoryKind.humidity:
        return Icons.water_drop_outlined;
      case AdvisoryKind.wind:
        return Icons.air;
      case AdvisoryKind.rain:
        return Icons.umbrella_outlined;
    }
  }
}
