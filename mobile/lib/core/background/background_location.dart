import 'package:geolocator/geolocator.dart';

import '../../features/location/data/last_location_store.dart';
import '../../features/location/domain/entities/coordinates.dart';
import '../config/app_config.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';

/// Phân giải toạ độ dùng trong background isolate (worker, alarm, bản tin).
///
/// Thứ tự: (1) `getLastKnownPosition` nếu tuổi ≤ ngưỡng; (2) fallback toạ độ đã
/// lưu ở [LastLocationStore] (lần định vị foreground gần nhất) — để nền vẫn fetch
/// được khi máy đứng yên cả đêm (last-known hết hạn). null → bỏ qua chu kỳ.
///
/// [source] chỉ dùng cho nhật ký (biết lớp nào đang hỏi vị trí).
Future<Coordinates?> resolveBackgroundCoords({
  String source = LogSource.ui,
}) async {
  try {
    final pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      final age = DateTime.now().difference(pos.timestamp);
      if (age <= const Duration(hours: AppConfig.backgroundLastKnownMaxAgeHours)) {
        final coords =
            Coordinates(latitude: pos.latitude, longitude: pos.longitude);
        // Refresh cache toạ độ để lần sau vẫn có fallback tươi.
        await LastLocationStore().save(coords);
        await AppLog.i(
          source,
          LogTags.loc,
          'vị trí từ last-known của hệ thống',
          data: {
            'toạ độ': '${pos.latitude.toStringAsFixed(4)},'
                '${pos.longitude.toStringAsFixed(4)}',
            'tuổi': _age(age),
          },
        );
        return coords;
      }
      await AppLog.i(
        source,
        LogTags.loc,
        'last-known quá cũ → thử toạ độ đã lưu',
        data: {
          'tuổi': _age(age),
          'trần': '${AppConfig.backgroundLastKnownMaxAgeHours}h',
        },
      );
    } else {
      await AppLog.i(
        source,
        LogTags.loc,
        'hệ thống không có last-known → thử toạ độ đã lưu',
      );
    }

    final stored = await LastLocationStore().read();
    if (stored == null) {
      await AppLog.w(
        source,
        LogTags.loc,
        'KHÔNG có vị trí nào → bỏ chu kỳ (mở app một lần để lấy vị trí)',
      );
      return null;
    }
    await AppLog.i(
      source,
      LogTags.loc,
      'vị trí từ bộ nhớ app (LastLocationStore)',
      data: {
        'toạ độ': '${stored.latitude.toStringAsFixed(4)},'
            '${stored.longitude.toStringAsFixed(4)}',
      },
    );
    return stored;
  } catch (e, st) {
    await AppLog.e(
      source,
      LogTags.loc,
      'lỗi khi phân giải vị trí nền',
      error: e,
      stack: st,
    );
    return null;
  }
}

String _age(Duration d) =>
    d.inHours >= 1 ? '${d.inHours}h${d.inMinutes % 60}p' : '${d.inMinutes}p';
