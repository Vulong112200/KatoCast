import 'package:dio/dio.dart';

import '../../../../core/config/app_config.dart';
import '../../domain/entities/coordinates.dart';
import '../../domain/entities/place.dart';

/// Reverse geocoding qua Nominatim (OpenStreetMap): toạ độ → địa chỉ tiếng Việt
/// chi tiết (đường → phường → quận → thành phố). Dùng thay/bổ sung plugin
/// `geocoding` vốn trả rất ít thông tin ở Việt Nam (thường chỉ có tỉnh/thành).
///
/// Chính sách OSM yêu cầu: gửi User-Agent rõ ràng và ≤ ~1 req/s — app chỉ gọi
/// khi đổi vị trí / refresh nên không vi phạm. Trả null khi lỗi mạng / rỗng để
/// caller fallback sang plugin nền tảng, KHÔNG chặn UI.
class NominatimDataSource {
  final Dio _dio;

  NominatimDataSource([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              responseType: ResponseType.json,
              headers: {'User-Agent': AppConfig.userAgent},
            ));

  Future<Place?> reverseGeocode(Coordinates coords) async {
    try {
      final res = await _dio.get<dynamic>(
        AppConfig.nominatimReverseUrl,
        queryParameters: {
          'format': 'jsonv2',
          'lat': coords.latitude,
          'lon': coords.longitude,
          // zoom 18 = mức đường phố; addressdetails=1 để tách phường/quận.
          'zoom': 18,
          'addressdetails': 1,
          'accept-language': 'vi',
        },
      );

      final data = res.data;
      if (data is! Map) return null;
      final addr = data['address'];
      if (addr is! Map) return null;

      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = addr[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final country = pick(['country']);

      // Đường + số nhà (nếu có): "63 Lý Tự Trọng".
      final road = pick(['road', 'pedestrian', 'footway']);
      final houseNo = pick(['house_number']);
      final thoroughfare = road == null
          ? null
          : (houseNo != null ? '$houseNo $road' : road);

      // Tỉnh/thành cấp cao nhất: theo cấu trúc hành chính VN mới, Nominatim
      // KHÔNG luôn đặt tên tỉnh/thành trực thuộc TW vào key `address` (vd điểm ở
      // TP.HCM: `city`="Thành phố Thủ Đức", còn "Thành phố Hồ Chí Minh" chỉ nằm
      // trong `display_name`). Vì vậy: ưu tiên key state/region/province nếu có,
      // fallback lấy token cuối cùng của `display_name` (bỏ quốc gia + mã bưu
      // chính) — luôn là đơn vị hành chính lớn nhất.
      final administrativeArea = pick(['state', 'region', 'province']) ??
          _topFromDisplayName(data['display_name'], country);

      // Quận/huyện / thành phố thuộc tỉnh (cấp trung gian, vd "Thành phố Thủ Đức").
      var subAdmin = pick([
        'city_district',
        'district',
        'county',
        'city',
        'town',
        'municipality',
      ]);
      // Tránh trùng cấp tỉnh (điểm nông thôn: city == tỉnh).
      if (subAdmin != null &&
          administrativeArea != null &&
          subAdmin.toLowerCase() == administrativeArea.toLowerCase()) {
        subAdmin = null;
      }

      return Place(
        coordinates: coords,
        thoroughfare: thoroughfare,
        // Phường/xã (ưu tiên phường trước khu phố/tổ dân phố).
        subLocality: pick(['quarter', 'ward', 'suburb', 'neighbourhood']),
        subAdministrativeArea: subAdmin,
        administrativeArea: administrativeArea,
        country: country,
      );
    } catch (_) {
      return null;
    }
  }

  /// Lấy đơn vị hành chính lớn nhất (tỉnh/thành) từ `display_name` của Nominatim
  /// — chuỗi dạng "…, `quận`, `tỉnh/thành`, `mã bưu chính`, `quốc gia`". Bỏ quốc
  /// gia ở cuối + các token toàn số (mã bưu chính) rồi lấy token còn lại cuối
  /// cùng. Trả null nếu không tách được.
  static String? _topFromDisplayName(dynamic displayName, String? country) {
    if (displayName is! String || displayName.trim().isEmpty) return null;
    final parts = displayName
        .split(',')
        .map((e) => e.trim())
        .where((p) {
          if (p.isEmpty) return false;
          if (country != null && p.toLowerCase() == country.toLowerCase()) {
            return false;
          }
          // Mã bưu chính (toàn chữ số).
          if (RegExp(r'^\d+$').hasMatch(p)) return false;
          return true;
        })
        .toList();
    return parts.isEmpty ? null : parts.last;
  }
}
