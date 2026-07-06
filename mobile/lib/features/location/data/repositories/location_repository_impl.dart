import 'package:dartz/dartz.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/coordinates.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/location_repository.dart';
import '../datasources/location_datasource.dart';
import '../datasources/nominatim_datasource.dart';

class LocationRepositoryImpl implements LocationRepository {
  final LocationDataSource _dataSource;
  final NominatimDataSource _nominatim;
  LocationRepositoryImpl(this._dataSource, this._nominatim);

  @override
  Future<Either<Failure, Coordinates>> getCurrentLocation() async {
    try {
      // Tối ưu last-known nằm TRONG getCurrentPosition (đã xin quyền trước) để
      // bảo đảm hộp thoại quyền luôn hiện trước khi đọc vị trí.
      final pos = await _dataSource.getCurrentPosition();
      return Right(_toCoordinates(pos));
    } on LocationPermissionException catch (e) {
      return Left(PermissionFailure(
        e.message,
        permanentlyDenied: e.permanentlyDenied,
      ));
    } catch (_) {
      return const Left(UnexpectedFailure('Không lấy được vị trí hiện tại.'));
    }
  }

  @override
  Stream<Coordinates> watchLocation() {
    return _dataSource.watchPosition().map(_toCoordinates);
  }

  @override
  Future<Coordinates?> getLastKnownLocation() async {
    final pos = await _dataSource.getLastKnown();
    return pos == null ? null : _toCoordinates(pos);
  }

  @override
  Future<Place?> getPlace(Coordinates coords) async {
    // Ưu tiên Nominatim (địa chỉ VN chi tiết: đường/phường/quận). Chỉ nhận kết
    // quả khi có ít nhất một cấp dưới tỉnh/thành để chắc chắn chi tiết hơn
    // plugin; nếu không → fallback plugin nền tảng (hoạt động offline).
    final osm = await _nominatim.reverseGeocode(coords);
    if (osm != null &&
        (osm.thoroughfare != null ||
            osm.subLocality != null ||
            osm.subAdministrativeArea != null)) {
      return osm;
    }

    final mark = await _dataSource.reverseGeocode(
      coords.latitude,
      coords.longitude,
    );
    if (mark == null) return osm; // giữ kết quả Nominatim (tỉnh/thành) nếu có.
    return Place(
      coordinates: coords,
      subLocality: mark.subLocality,
      locality: mark.locality,
      subAdministrativeArea: mark.subAdministrativeArea,
      administrativeArea: mark.administrativeArea,
      country: mark.country,
    );
  }

  Coordinates _toCoordinates(Position p) =>
      Coordinates(latitude: p.latitude, longitude: p.longitude);
}
