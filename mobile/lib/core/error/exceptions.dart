// Exceptions tầng Data (datasource ném ra). Repository sẽ bắt và chuyển thành
// Failure (xem `failures.dart`) để tầng trên xử lý mà không phụ thuộc Dio.

/// Lỗi gọi server (HTTP != 2xx, payload lỗi, key sai...).
class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException(this.message, {this.statusCode});
  @override
  String toString() => 'ServerException($statusCode): $message';
}

/// Mất kết nối mạng / timeout.
class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Không có kết nối mạng']);
  @override
  String toString() => 'NetworkException: $message';
}

/// Không có dữ liệu trong cache local.
class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Không có dữ liệu cache']);
  @override
  String toString() => 'CacheException: $message';
}

/// Người dùng từ chối quyền / dịch vụ vị trí tắt.
class LocationPermissionException implements Exception {
  final String message;

  /// true nếu bị từ chối vĩnh viễn (cần mở Settings thủ công).
  final bool permanentlyDenied;
  const LocationPermissionException(
    this.message, {
    this.permanentlyDenied = false,
  });
  @override
  String toString() => 'LocationPermissionException: $message';
}
