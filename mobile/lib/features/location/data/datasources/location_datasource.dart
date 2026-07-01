import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/permissions/permission_service.dart';

/// Datasource định vị — bọc geolocator. Đảm bảo quyền trước khi đọc vị trí.
class LocationDataSource {
  final PermissionService _permissions;
  LocationDataSource(this._permissions);

  Future<Position> getCurrentPosition() async {
    // Xin quyền TRƯỚC (hiện hộp thoại nếu cần) — bắt buộc trước mọi lần đọc vị
    // trí, kể cả last-known.
    await _permissions.ensureLocationPermission();

    // Sau khi có quyền: ưu tiên vị trí "last-known" cho phản hồi tức thì (đủ
    // chính xác cho cache thời tiết key theo toạ độ làm tròn ~1km) → tránh chờ
    // GPS độ chính xác cao lúc mở app.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;

    // Chưa có last-known (vd lần đầu) → lấy vị trí hiện tại, kèm giới hạn thời
    // gian để không treo UI vô hạn nếu không bắt được tín hiệu.
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  /// Stream cập nhật khi di chuyển >= distanceFilter mét (tối ưu pin).
  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConfig.locationDistanceFilterMeters,
      ),
    );
  }

  Future<Position?> getLastKnown() => Geolocator.getLastKnownPosition();

  /// Reverse geocoding: toạ độ -> địa danh. Trả null khi không có kết quả,
  /// lỗi mạng, hoặc thiết bị không có dịch vụ geocoding (không chặn UI).
  Future<Placemark?> reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      return placemarks.isEmpty ? null : placemarks.first;
    } catch (_) {
      return null;
    }
  }
}
