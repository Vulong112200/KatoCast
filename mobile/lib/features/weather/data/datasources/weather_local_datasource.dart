import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../location/domain/entities/coordinates.dart';

/// Cache thời tiết trong Drift để fallback offline.
class WeatherLocalDataSource {
  final AppDatabase _db;
  WeatherLocalDataSource(this._db);

  Future<void> cache(Coordinates coords, Map<String, dynamic> payload,
      DateTime fetchedAt) async {
    await _db.into(_db.weatherCache).insertOnConflictUpdate(
          WeatherCacheCompanion.insert(
            locationKey: coords.cacheKey,
            payloadJson: jsonEncode(payload),
            fetchedAt: fetchedAt,
          ),
        );
  }

  /// Trả (payload, fetchedAt) hoặc null nếu chưa có cache cho toạ độ này.
  Future<(Map<String, dynamic>, DateTime)?> read(Coordinates coords) async {
    final row = await (_db.select(_db.weatherCache)
          ..where((t) => t.locationKey.equals(coords.cacheKey)))
        .getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return (json, row.fetchedAt);
  }
}
