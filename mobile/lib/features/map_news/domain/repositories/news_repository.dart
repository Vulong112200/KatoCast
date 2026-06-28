import '../../../location/domain/entities/coordinates.dart';

/// MODULE 1 — Bản đồ & Tin tức quanh vị trí.
///
/// Implementation hiện tại: [NewsRepositoryImpl] đọc RSS thời tiết (miễn phí);
/// bản đồ dùng OpenStreetMap (flutter_map). RSS không geo-tag nên [center]/
/// [radiusMeters] chưa lọc theo vị trí (giữ trong API để đổi nguồn sau).
class NewsItem {
  final String title;
  final String url;
  final DateTime? publishedAt;
  final Coordinates? location;
  const NewsItem({
    required this.title,
    required this.url,
    this.publishedAt,
    this.location,
  });
}

abstract class NewsRepository {
  /// Lấy tin tức quanh toạ độ trong bán kính [radiusMeters].
  Future<List<NewsItem>> getNewsAround(
    Coordinates center, {
    required int radiusMeters,
  });
}
