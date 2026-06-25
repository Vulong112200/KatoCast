import 'package:geolocator/geolocator.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/permissions/permission_service.dart';

/// Datasource định vị — bọc geolocator. Đảm bảo quyền trước khi đọc vị trí.
class LocationDataSource {
  final PermissionService _permissions;
  LocationDataSource(this._permissions);

  Future<Position> getCurrentPosition() async {
    await _permissions.ensureLocationPermission();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
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
}
