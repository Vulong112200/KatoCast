import 'dart:async';

/// Hàng đợi FIFO cho MỌI lời xin quyền runtime của app.
///
/// ⚠️ VÌ SAO CẦN: Android chỉ cho phép **một** hộp thoại quyền tại một thời điểm
/// cho mỗi Activity. Nếu gọi `requestPermissions()` lần thứ hai trong khi hộp
/// thoại đầu còn hiển thị, hệ thống **bỏ qua lời gọi đó VÀ KHÔNG bao giờ gửi
/// callback kết quả** — future của plugin không bao giờ hoàn tất.
///
/// Đó chính là lỗi "cài mới → hiện xin quyền thông báo → bấm xong thì app đứng
/// đơ, màn hình trắng, không hiện xin quyền vị trí; phải vuốt tắt app rồi mở
/// lần 2 mới thấy": lúc khởi động có HAI plugin cùng xin quyền qua hai đường
/// khác nhau —
/// - `permission_handler` xin `POST_NOTIFICATIONS` từ `main._bootstrap()`;
/// - `geolocator` xin `ACCESS_FINE_LOCATION` từ `currentLocationProvider`
///   (bị kích hoạt ngay trong frame đầu khi `WeatherScreen` build).
/// Lời gọi tới sau bị hệ thống thả im lặng → `currentLocationProvider` treo
/// mãi ở trạng thái loading → `WeatherScreen` xoay vòng vô hạn. Mở lại app lần
/// hai thì quyền thông báo đã có nên không còn tranh chấp, mọi thứ "tự hết".
///
/// Cách chữa duy nhất đúng là **xếp hàng**: mỗi lượt xin quyền chỉ bắt đầu sau
/// khi lượt trước kết thúc (dù thành công, bị từ chối, hay lỗi).
///
/// Lưu ý: static nên phạm vi là MỘT isolate — đúng ý muốn, vì chỉ isolate main
/// (có Activity) mới hiện được hộp thoại quyền.
class PermissionGate {
  PermissionGate._();

  /// Đuôi hàng đợi: future của lượt xin quyền đang/vừa chạy.
  static Future<void> _tail = Future<void>.value();

  /// Chạy [action] khi hàng đợi tới lượt. Trả đúng kết quả/lỗi của [action].
  ///
  /// `_tail.then` đăng ký ĐỒNG BỘ ngay khi gọi, nên thứ tự thực thi bằng đúng
  /// thứ tự gọi (FIFO) — nhờ đó thứ tự hộp thoại quyền là xác định được, không
  /// còn phụ thuộc vào việc plugin nào trả lời nhanh hơn.
  static Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // Lượt sau chờ lượt này xong; lỗi của lượt này không được làm đứt hàng đợi.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
