import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/domain/entities/coordinates.dart';
import '../../../location/presentation/providers/location_provider.dart';
import '../../data/datasources/rss_datasource.dart';
import '../../data/repositories/news_repository_impl.dart';
import '../../domain/repositories/news_repository.dart';

// --- DI ---
final rssDataSourceProvider = Provider<RssDataSource>(
  (ref) => RssDataSource(),
);

final newsRepositoryProvider = Provider<NewsRepository>(
  (ref) => NewsRepositoryImpl(ref.watch(rssDataSourceProvider)),
);

/// Tin tức thời tiết/cảnh báo quanh vị trí hiện tại. Lỗi → danh sách rỗng
/// (đã nuốt trong datasource), không chặn bản đồ.
final newsProvider = FutureProvider<List<NewsItem>>((ref) async {
  final repo = ref.watch(newsRepositoryProvider);
  // Dùng vị trí nếu có; không có cũng vẫn lấy được feed (RSS không geo-tag).
  final coords = await ref.watch(currentLocationProvider.future).then<Coordinates?>(
        (c) => c,
        onError: (_) => null,
      );
  return repo.getNewsAround(
    coords ?? const Coordinates(latitude: 0, longitude: 0),
    radiusMeters: 50000,
  );
});
