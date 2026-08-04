import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/coordinates.dart';

/// Toạ độ đã lưu + THỜI ĐIỂM lưu.
class StoredCoords {
  final Coordinates coords;

  /// Lúc toạ độ này được ghi. null nếu bản ghi có từ phiên bản cũ (chưa có mốc).
  final DateTime? savedAt;

  const StoredCoords(this.coords, this.savedAt);

  /// Tuổi của toạ độ; null nếu không biết mốc lưu.
  Duration? get age =>
      savedAt == null ? null : DateTime.now().difference(savedAt!);
}

/// Lưu toạ độ lần định vị/fetch thành công gần nhất (SharedPreferences).
///
/// Class thuần (không phụ thuộc Flutter) nên dùng chung cho background isolate
/// (WorkManager / AlarmManager) lẫn foreground. Mục đích: khi nền không lấy được
/// `getLastKnownPosition`, vẫn có toạ độ để fetch thời tiết — tránh việc
/// worker/bản tin bỏ qua cả đêm khi máy đứng yên.
///
/// ⚠️ Trước đây store này KHÔNG lưu thời điểm, nên không ai biết toạ độ đang
/// dùng cũ bao lâu. Đó là lỗ hổng thật: nhật ký cho thấy nền LUÔN rơi vào nhánh
/// này (`getLastKnownPosition` trả null), nghĩa là khi người dùng di chuyển thì
/// nền vẫn báo thời tiết của chỗ CŨ mà không có dấu hiệu nào. Nay có [savedAt]
/// để nhật ký nói rõ tuổi và để `resolveBackgroundCoords` biết khi nào cần xin
/// một fix vị trí tươi.
class LastLocationStore {
  static const _kLat = 'last_location_lat';
  static const _kLng = 'last_location_lng';
  static const _kSavedAtMs = 'last_location_saved_ms';

  /// Ghi toạ độ mới nhất. Gọi sau mỗi lần fetch/định vị thành công.
  Future<void> save(Coordinates coords, {DateTime? at}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, coords.latitude);
    await prefs.setDouble(_kLng, coords.longitude);
    await prefs.setInt(
      _kSavedAtMs,
      (at ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  /// Đọc toạ độ đã lưu; null nếu chưa từng lưu.
  Future<Coordinates?> read() async => (await readStored())?.coords;

  /// Đọc toạ độ đã lưu KÈM thời điểm lưu.
  ///
  /// `reload()` vì mỗi isolate giữ một bản cache SharedPreferences riêng: không
  /// nạp lại thì isolate sống lâu (foreground service) sẽ không thấy toạ độ mới
  /// do isolate khác / màn hình app ghi.
  Future<StoredCoords?> readStored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final lat = prefs.getDouble(_kLat);
    final lng = prefs.getDouble(_kLng);
    if (lat == null || lng == null) return null;
    final ms = prefs.getInt(_kSavedAtMs);
    return StoredCoords(
      Coordinates(latitude: lat, longitude: lng),
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
