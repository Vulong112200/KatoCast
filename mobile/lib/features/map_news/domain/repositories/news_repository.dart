import '../../../location/domain/entities/coordinates.dart';

/// MODULE 1 (Phase 2) — Bản đồ & Tin tức quanh vị trí.
///
/// Interface đã định nghĩa sẵn để tầng UI/usecase code trước. Implementation
/// thật (Map SDK + RSS/News API) sẽ thêm sau mà không đụng tới core thời tiết.
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
