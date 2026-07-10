import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/entities/exam_event.dart';

/// Gọi backend KatoAssistant lấy lịch có cấu trúc (exam_events).
///
/// Cùng mẫu với [AnnouncementRemoteDataSource]: dùng [ApiClient] trỏ
/// [AppConfig.backendBaseUrl].
class EventRemoteDataSource {
  final ApiClient _client;

  EventRemoteDataSource([ApiClient? client])
      : _client = client ?? ApiClient.create(baseUrl: AppConfig.backendBaseUrl);

  /// GET /api/v1/events?topic=
  Future<List<ExamEvent>> fetch({String? topic}) async {
    final params = <String, dynamic>{};
    if (topic != null) params['topic'] = topic;
    final resp = await _client.dio.get<List<dynamic>>(
      '/api/v1/events',
      queryParameters: params,
    );
    final data = resp.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ExamEvent.fromJson)
        .toList();
  }
}
