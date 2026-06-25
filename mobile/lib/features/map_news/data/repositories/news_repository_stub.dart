import '../../../location/domain/entities/coordinates.dart';
import '../../domain/repositories/news_repository.dart';

/// STUB (Phase 2). Hàm rỗng — chưa gọi API thật.
///
/// TODO(Phase 2): tích hợp Map SDK (Google Maps / Mapbox) để hiển thị bản đồ
/// và nguồn tin (RSS feed hoặc News API như NewsAPI.org / GNews) lọc theo
/// toạ độ + bán kính. Trả [NewsItem] kèm vị trí để ghim lên bản đồ.
class NewsRepositoryStub implements NewsRepository {
  const NewsRepositoryStub();

  @override
  Future<List<NewsItem>> getNewsAround(
    Coordinates center, {
    required int radiusMeters,
  }) async {
    throw UnimplementedError(
      'NewsRepository chưa triển khai (Phase 2 — Map SDK + RSS/News API).',
    );
  }
}
