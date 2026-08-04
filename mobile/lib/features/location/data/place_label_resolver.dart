import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/coordinates.dart';
import '../domain/entities/place.dart';
import 'datasources/nominatim_datasource.dart';

/// Đổi toạ độ thành ĐỊA CHỈ ĐẦY ĐỦ dạng chữ (số nhà → đường → phường/xã →
/// quận/huyện → tỉnh/thành) dùng được từ MỌI isolate, kể cả isolate nền.
///
/// Vì sao tồn tại: nhật ký hoạt động trước đây chỉ ghi toạ độ và một nhãn rất
/// thô ("Thành phố Hồ Chí Minh, Hồ Chí Minh") vì nó gọi thẳng plugin
/// `geocoding` — plugin này ở Việt Nam gần như luôn chỉ trả tới cấp tỉnh/thành.
/// Nhìn `10.8524,106.6507` thì người dùng không thể biết app đang lấy thời tiết
/// đúng chỗ mình đứng hay không. App đã có [NominatimDataSource] cho địa chỉ VN
/// chi tiết (màn Thời tiết dùng nó), nên đường nền chỉ cần dùng lại.
///
/// Ba điều phải cẩn thận khi dùng Nominatim ở đường nền:
/// 1. **Chính sách OSM**: tối đa ~1 request/giây và không được dùng ồ ạt tự
///    động. Chu kỳ nền chạy mỗi 5–15' × 3 lớp trigger, nên phải có CACHE và
///    hàng rào giãn cách ([minCallGap]).
/// 2. **Nhiễu GPS**: nhật ký thật cho thấy toạ độ rung 0–51m dù máy đứng yên.
///    Cache vì vậy so theo KHOẢNG CÁCH ([reuseRadiusMeters]) chứ không so khoá
///    làm tròn — làm tròn thì một bước nhiễu qua biên là mất cache.
/// 3. **Không được làm hỏng chu kỳ**: mọi lỗi/timeout đều rơi về plugin
///    `geocoding`, và cuối cùng là null. Hàm này KHÔNG BAO GIỜ ném lỗi.
class PlaceLabelResolver {
  const PlaceLabelResolver._();

  static const String _kLat = 'place_label_lat';
  static const String _kLng = 'place_label_lng';
  static const String _kLabel = 'place_label_text';
  static const String _kAtMs = 'place_label_at_ms';
  static const String _kLastCallMs = 'place_label_last_call_ms';

  /// Còn trong bán kính này so với điểm đã tra thì DÙNG LẠI nhãn cũ (địa chỉ
  /// không đổi trong ~150m, và đây là mức che được nhiễu GPS quan sát thực tế).
  static const double reuseRadiusMeters = 150;

  /// Nhãn cũ hơn ngưỡng này thì tra lại (đề phòng đổi tên đơn vị hành chính).
  static const Duration maxAge = Duration(hours: 12);

  /// Giãn cách tối thiểu giữa hai lần gọi Nominatim từ BẤT KỲ isolate nào.
  static const Duration minCallGap = Duration(minutes: 1);

  /// Địa chỉ đầy đủ của [coords], hoặc null nếu không tra được bằng cách nào.
  ///
  /// [remote] cho phép test tiêm data source giả.
  static Future<String?> describe(
    Coordinates coords, {
    NominatimDataSource? remote,
  }) async {
    final cached = await _readCache(coords);
    if (cached != null) return cached;

    if (await _claimRemoteCall()) {
      try {
        final place = await (remote ?? NominatimDataSource())
            .reverseGeocode(coords)
            .timeout(const Duration(seconds: 8));
        final label = _labelOf(place);
        if (label != null) {
          await _writeCache(coords, label);
          return label;
        }
      } catch (_) {
        // Mạng lỗi/timeout → rơi xuống plugin nền tảng bên dưới.
      }
    }

    // Fallback: plugin nền tảng. Thô hơn (thường chỉ tới tỉnh/thành ở VN) nên
    // KHÔNG cache — để lượt sau còn thử lại Nominatim thay vì khoá 12 tiếng.
    return _fromPlugin(coords);
  }

  /// Nhãn đầy đủ nhất có thể từ [place]; null nếu Nominatim không trả tên nào
  /// (khi đó `fullLabel` chỉ là toạ độ — vô nghĩa để in cạnh toạ độ).
  static String? _labelOf(Place? place) {
    if (place == null) return null;
    final hasName = (place.thoroughfare ?? place.subLocality ?? place.locality ??
            place.subAdministrativeArea ?? place.administrativeArea) !=
        null;
    return hasName ? place.fullLabel : null;
  }

  static Future<String?> _fromPlugin(Coordinates coords) async {
    try {
      final marks = await geo
          .placemarkFromCoordinates(coords.latitude, coords.longitude)
          .timeout(const Duration(seconds: 6));
      if (marks.isEmpty) return null;
      final m = marks.first;
      final place = Place(
        coordinates: coords,
        thoroughfare: m.thoroughfare,
        subLocality: m.subLocality,
        locality: m.locality,
        subAdministrativeArea: m.subAdministrativeArea,
        administrativeArea: m.administrativeArea,
        country: m.country,
      );
      return _labelOf(place);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readCache(Coordinates coords) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // `reload()`: isolate foreground service sống hàng giờ, không nạp lại thì
      // không thấy nhãn do isolate alarm/UI vừa ghi → tra lại Nominatim vô ích.
      await prefs.reload();
      final label = prefs.getString(_kLabel);
      final lat = prefs.getDouble(_kLat);
      final lng = prefs.getDouble(_kLng);
      final atMs = prefs.getInt(_kAtMs);
      if (label == null || lat == null || lng == null || atMs == null) {
        return null;
      }
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(atMs));
      if (age > maxAge) return null;
      final moved = Geolocator.distanceBetween(
          lat, lng, coords.latitude, coords.longitude);
      return moved <= reuseRadiusMeters ? label : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(Coordinates coords, String label) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLabel, label);
      await prefs.setDouble(_kLat, coords.latitude);
      await prefs.setDouble(_kLng, coords.longitude);
      await prefs.setInt(_kAtMs, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Không cache được → lượt sau tra lại (vẫn bị [minCallGap] chặn bớt).
    }
  }

  /// Có được phép gọi Nominatim lúc này không (tôn trọng chính sách OSM). Ghi
  /// mốc gọi TRƯỚC khi gọi để hai isolate không cùng bắn một lúc.
  static Future<bool> _claimRemoteCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastMs = prefs.getInt(_kLastCallMs) ?? 0;
      if (lastMs != 0 && nowMs - lastMs < minCallGap.inMilliseconds) {
        return false;
      }
      await prefs.setInt(_kLastCallMs, nowMs);
      return true;
    } catch (_) {
      // Không đọc được mốc → cho gọi (một request lẻ không vi phạm gì).
      return true;
    }
  }

  /// Nạp SẴN cache từ một [Place] đã tra ở đường UI (màn Thời tiết) — để isolate
  /// nền dùng lại đúng địa chỉ đó mà không tốn thêm request Nominatim.
  static Future<void> seedCache(Coordinates coords, Place place) async {
    final label = _labelOf(place);
    if (label != null) await _writeCache(coords, label);
  }

  /// Chỉ dùng cho TEST: xoá cache + mốc giãn cách.
  static Future<void> debugReset() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kLabel, _kLat, _kLng, _kAtMs, _kLastCallMs]) {
      await prefs.remove(k);
    }
  }
}
