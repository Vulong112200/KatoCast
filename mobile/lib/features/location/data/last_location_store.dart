import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/coordinates.dart';

/// Lưu toạ độ lần định vị/fetch thành công gần nhất (SharedPreferences).
///
/// Class thuần (không phụ thuộc Flutter) nên dùng chung cho background isolate
/// (WorkManager / AlarmManager) lẫn foreground. Mục đích: khi nền không lấy
/// được `getLastKnownPosition` (null hoặc quá cũ), vẫn có toạ độ để fetch thời
/// tiết — tránh việc worker/bản tin bỏ qua cả đêm khi máy đứng yên.
class LastLocationStore {
  static const _kLat = 'last_location_lat';
  static const _kLng = 'last_location_lng';

  /// Ghi toạ độ mới nhất. Gọi sau mỗi lần fetch/định vị thành công.
  Future<void> save(Coordinates coords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, coords.latitude);
    await prefs.setDouble(_kLng, coords.longitude);
  }

  /// Đọc toạ độ đã lưu; null nếu chưa từng lưu.
  Future<Coordinates?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLat);
    final lng = prefs.getDouble(_kLng);
    if (lat == null || lng == null) return null;
    return Coordinates(latitude: lat, longitude: lng);
  }
}
