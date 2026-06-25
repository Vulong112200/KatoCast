import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';

/// Chuyển bất kỳ lỗi nào thành message tiếng Việt thân thiện để hiển thị.
///
/// Theo CLAUDE.md: UI KHÔNG được hiển thị `$e` thô. Mọi nơi cần text lỗi
/// đều đi qua hàm này.
String extractUserMessage(Object error) {
  if (error is Failure) return error.userMessage;
  if (error is LocationPermissionException) return error.message;
  if (error is NetworkException) {
    return 'Mất kết nối mạng. Vui lòng kiểm tra Internet.';
  }
  if (error is ServerException) {
    return error.message;
  }
  if (error is CacheException) {
    return 'Chưa có dữ liệu offline. Hãy kết nối mạng để tải.';
  }
  return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
}
