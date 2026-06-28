import 'package:dio/dio.dart';

import '../../domain/entities/poi.dart';
import '../../domain/entities/route_point.dart';

/// Kết quả thô 1 POI từ Overpass (chưa tính khoảng cách tới lộ trình).
class OverpassPoi {
  final String name;
  final PoiType type;
  final double latitude;
  final double longitude;

  const OverpassPoi({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });
}

/// Truy vấn tiện ích (POI) từ Overpass API của OpenStreetMap — MIỄN PHÍ,
/// không cần API key. Dùng Dio riêng (base URL Overpass, khác OWM).
class OverpassDataSource {
  final Dio _dio;

  OverpassDataSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://overpass-api.de/api',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
            ));

  /// Tag OSM amenity/shop tương ứng từng PoiType.
  static const Map<PoiType, ({String key, String value})> _osmTag = {
    PoiType.restaurant: (key: 'amenity', value: 'restaurant'),
    PoiType.gasStation: (key: 'amenity', value: 'fuel'),
    PoiType.cafe: (key: 'amenity', value: 'cafe'),
    PoiType.supermarket: (key: 'shop', value: 'supermarket'),
  };

  /// Quét các POI thuộc [types] trong [radiusMeters] quanh tất cả [points].
  /// Trả danh sách thô (có thể trùng — repository sẽ khử trùng + tính khoảng cách).
  Future<List<OverpassPoi>> fetchPois(
    List<RoutePoint> points, {
    required int radiusMeters,
    required List<PoiType> types,
  }) async {
    if (points.isEmpty || types.isEmpty) return [];

    final query = _buildQuery(points, radiusMeters, types);
    final res = await _dio.post<dynamic>(
      '/interpreter',
      data: 'data=${Uri.encodeQueryComponent(query)}',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        responseType: ResponseType.json,
      ),
    );

    final data = res.data;
    if (data is! Map || data['elements'] is! List) return [];

    final out = <OverpassPoi>[];
    for (final el in (data['elements'] as List)) {
      if (el is! Map) continue;
      final tags = el['tags'];
      if (tags is! Map) continue;

      final type = _matchType(tags, types);
      if (type == null) continue;

      // node có lat/lon trực tiếp; way/relation có "center".
      final lat = (el['lat'] ?? el['center']?['lat']) as num?;
      final lon = (el['lon'] ?? el['center']?['lon']) as num?;
      if (lat == null || lon == null) continue;

      final name = (tags['name'] as String?)?.trim();
      out.add(OverpassPoi(
        name: (name == null || name.isEmpty) ? _fallbackName(type) : name,
        type: type,
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
      ));
    }
    return out;
  }

  /// Xác định PoiType từ tags OSM (chỉ trong [requested]).
  PoiType? _matchType(Map tags, List<PoiType> requested) {
    for (final t in requested) {
      final tag = _osmTag[t]!;
      if (tags[tag.key] == tag.value) return t;
    }
    return null;
  }

  String _fallbackName(PoiType type) {
    switch (type) {
      case PoiType.restaurant:
        return 'Nhà hàng';
      case PoiType.gasStation:
        return 'Cây xăng';
      case PoiType.cafe:
        return 'Quán cà phê';
      case PoiType.supermarket:
        return 'Siêu thị';
    }
  }

  /// Dựng Overpass QL: với mỗi (point × type) thêm 1 mệnh đề around.
  /// `out center` để way/relation cũng có toạ độ tâm.
  String _buildQuery(
    List<RoutePoint> points,
    int radiusMeters,
    List<PoiType> types,
  ) {
    final buffer = StringBuffer('[out:json][timeout:25];(');
    for (final p in points) {
      for (final t in types) {
        final tag = _osmTag[t]!;
        final around = 'around:$radiusMeters,${p.latitude},${p.longitude}';
        // node + way để bắt cả POI dạng điểm lẫn dạng vùng (siêu thị lớn).
        buffer.write('node["${tag.key}"="${tag.value}"]($around);');
        buffer.write('way["${tag.key}"="${tag.value}"]($around);');
      }
    }
    buffer.write(');out center;');
    return buffer.toString();
  }
}
