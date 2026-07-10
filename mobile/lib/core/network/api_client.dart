import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../error/exceptions.dart';

/// Factory + interceptor cho Dio.
///
/// Tầng network thuần: chỉ lo HTTP + map lỗi Dio → [exceptions]. KHÔNG chứa
/// business logic. Datasource dùng instance này; mặc định trỏ OpenWeatherMap,
/// truyền [baseUrl] để tạo client trỏ backend KatoAssistant (theo dõi thông báo).
class ApiClient {
  final Dio dio;

  ApiClient._(this.dio);

  factory ApiClient.create({String? baseUrl}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConfig.owmBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, handler) {
          // Chuyển DioException → exception nội bộ để repository xử lý đồng nhất.
          handler.reject(_mapError(e));
        },
      ),
    );

    return ApiClient._(dio);
  }

  static DioException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return e.copyWith(error: const NetworkException('Hết thời gian kết nối'));
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final msg = _extractApiMessage(e.response?.data) ??
            'Lỗi máy chủ thời tiết ($code)';
        return e.copyWith(error: ServerException(msg, statusCode: code));
      default:
        return e.copyWith(error: const NetworkException());
    }
  }

  /// OpenWeatherMap trả lỗi ở field `message`.
  static String? _extractApiMessage(dynamic data) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return null;
  }
}
