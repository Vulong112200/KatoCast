import 'package:dartz/dartz.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/coordinates.dart';
import '../../domain/repositories/location_repository.dart';
import '../datasources/location_datasource.dart';

class LocationRepositoryImpl implements LocationRepository {
  final LocationDataSource _dataSource;
  LocationRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, Coordinates>> getCurrentLocation() async {
    try {
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

  Coordinates _toCoordinates(Position p) =>
      Coordinates(latitude: p.latitude, longitude: p.longitude);
}
