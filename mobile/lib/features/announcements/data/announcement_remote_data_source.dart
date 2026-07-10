import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/entities/announcement.dart';

/// Gọi backend KatoAssistant lấy danh sách thông báo theo chủ đề.
///
/// Dùng [ApiClient] trỏ [AppConfig.backendBaseUrl] (KHÁC OpenWeatherMap). Trả
/// entity domain; lỗi Dio đã được ApiClient map sang exception nội bộ.
class AnnouncementRemoteDataSource {
  final ApiClient _client;

  AnnouncementRemoteDataSource([ApiClient? client])
      : _client = client ??
            ApiClient.create(baseUrl: AppConfig.backendBaseUrl);

  /// GET /api/v1/announcements?topic=&since= — [since] lọc first_seen_at >.
  Future<List<Announcement>> fetch({
    required String topic,
    DateTime? since,
    int limit = 100,
  }) async {
    final resp = await _client.dio.get<List<dynamic>>(
      '/api/v1/announcements',
      queryParameters: {
        'topic': topic,
        if (since != null) 'since': since.toUtc().toIso8601String(),
        'limit': limit,
      },
    );
    final data = resp.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(Announcement.fromJson)
        .toList();
  }
}
