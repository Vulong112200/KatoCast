import '../../../location/domain/entities/coordinates.dart';
import '../../domain/repositories/news_repository.dart';
import '../datasources/rss_datasource.dart';

/// Triển khai NewsRepository qua RSS (miễn phí).
///
/// RSS không có toạ độ nên [center]/[radiusMeters] hiện chưa dùng để lọc theo
/// vị trí — tin mang tính chủ đề thời tiết/cảnh báo. Tham số vẫn giữ trong
/// interface để sau này đổi sang nguồn có geo-tag mà không phá API.
class NewsRepositoryImpl implements NewsRepository {
  final RssDataSource _rss;
  const NewsRepositoryImpl(this._rss);

  @override
  Future<List<NewsItem>> getNewsAround(
    Coordinates center, {
    required int radiusMeters,
  }) {
    return _rss.fetchFeed();
  }
}
