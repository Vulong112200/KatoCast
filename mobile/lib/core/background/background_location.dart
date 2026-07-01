import 'package:geolocator/geolocator.dart';

import '../../features/location/data/last_location_store.dart';
import '../../features/location/domain/entities/coordinates.dart';
import '../config/app_config.dart';

/// Phân giải toạ độ dùng trong background isolate (worker 15' & bản tin alarm).
///
/// Thứ tự: (1) `getLastKnownPosition` nếu tuổi ≤ ngưỡng; (2) fallback toạ độ đã
/// lưu ở [LastLocationStore] (lần fetch/định vị foreground gần nhất) — để nền
/// vẫn fetch được khi máy đứng yên cả đêm (last-known hết hạn). null → bỏ qua.
Future<Coordinates?> resolveBackgroundCoords() async {
  final pos = await Geolocator.getLastKnownPosition();
  if (pos != null) {
    final age = DateTime.now().difference(pos.timestamp);
    if (age <= const Duration(hours: AppConfig.backgroundLastKnownMaxAgeHours)) {
      final coords =
          Coordinates(latitude: pos.latitude, longitude: pos.longitude);
      // Refresh cache toạ độ để lần sau vẫn có fallback tươi.
      await LastLocationStore().save(coords);
      return coords;
    }
  }
  // Last-known null/quá cũ → dùng toạ độ đã lưu.
  return LastLocationStore().read();
}
