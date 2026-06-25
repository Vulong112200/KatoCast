/// Failures — biểu diễn lỗi ở tầng Domain/Repository (không phụ thuộc framework).
///
/// Repository trả `Either<Failure, T>` (dartz). UI dùng [Failure.userMessage]
/// để hiển thị — KHÔNG hiển thị exception thô (theo CLAUDE.md).
sealed class Failure {
  final String userMessage;
  const Failure(this.userMessage);
}

/// Lỗi mạng (offline, timeout).
class NetworkFailure extends Failure {
  const NetworkFailure([
    super.userMessage =
        'Mất kết nối mạng. Vui lòng kiểm tra Internet và thử lại.',
  ]);
}

/// Lỗi từ server/API (key sai, 5xx, payload lỗi).
class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure(
    super.userMessage, {
    this.statusCode,
  });
}

/// Không có dữ liệu cache khi offline.
class CacheFailure extends Failure {
  const CacheFailure([
    super.userMessage = 'Chưa có dữ liệu offline. Hãy kết nối mạng để tải.',
  ]);
}

/// Quyền vị trí bị từ chối / dịch vụ định vị tắt.
class PermissionFailure extends Failure {
  final bool permanentlyDenied;
  const PermissionFailure(
    super.userMessage, {
    this.permanentlyDenied = false,
  });
}

/// Lỗi không xác định.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([
    super.userMessage = 'Đã có lỗi xảy ra. Vui lòng thử lại.',
  ]);
}
