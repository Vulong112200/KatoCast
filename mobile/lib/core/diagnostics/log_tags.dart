/// Nhãn `tag` chuẩn của nhật ký. Gom về một chỗ để (a) mọi nơi ghi cùng tên,
/// (b) trang Nhật ký lọc & dựng thẻ "Tình trạng" dựa vào tên ổn định thay vì
/// dò chuỗi tự do.
class LogTags {
  const LogTags._();

  /// Bắt đầu một chu kỳ nền (kèm alarm id / nguồn).
  static const String cycle = 'cycle';

  /// Kết quả kiểm tra khung giờ hoạt động.
  static const String window = 'window';

  /// Phân giải vị trí nền (toạ độ + nguồn + tuổi), hoặc lý do không có.
  static const String loc = 'loc';

  /// Quyết định dùng cache hay gọi API (guard quota).
  static const String source = 'source';

  /// Kết quả gọi API thời tiết (ok + thời lượng, hoặc lỗi).
  static const String fetch = 'fetch';

  /// Kết quả phân tích mưa / môi trường.
  static const String analyze = 'analyze';

  /// ĐÃ hiển thị thông báo (kèm id + tiêu đề).
  static const String notify = 'notify';

  /// KHÔNG hiển thị thông báo + lý do.
  static const String skip = 'skip';

  /// Đã đặt/đặt lại một alarm (kèm mốc kế tiếp).
  static const String arm = 'arm';

  /// Lock chu kỳ: bị bỏ lượt, hoặc chiếm lại lock quá hạn.
  static const String lock = 'lock';

  /// Trạng thái foreground service (bật/hồi sinh/không chạy).
  static const String service = 'service';

  /// Tầng dữ liệu cục bộ (Drift/SQLite) — đặc biệt là lỗi khoá DB.
  static const String db = 'db';

  /// Bản tin hằng ngày.
  static const String digest = 'digest';

  /// Poll tin mới (JLPT/MBA…).
  static const String announce = 'announce';

  /// Khởi động app / áp cấu hình nền.
  static const String boot = 'boot';
}
