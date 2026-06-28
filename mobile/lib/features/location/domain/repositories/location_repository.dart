import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/coordinates.dart';
import '../entities/place.dart';

/// Hợp đồng (interface) tầng Repository cho định vị.
/// UI/usecase phụ thuộc abstraction này, không phụ thuộc geolocator.
abstract class LocationRepository {
  /// Lấy vị trí hiện tại 1 lần (dùng khi mở app, hoặc trong background).
  Future<Either<Failure, Coordinates>> getCurrentLocation();

  /// Stream vị trí khi người dùng di chuyển (distanceFilter để tiết kiệm pin).
  Stream<Coordinates> watchLocation();

  /// Vị trí gần nhất đã biết (nhanh, có thể null) — dùng trong background task.
  Future<Coordinates?> getLastKnownLocation();

  /// Reverse geocoding: toạ độ -> địa danh. Null nếu không xác định được.
  Future<Place?> getPlace(Coordinates coords);
}
