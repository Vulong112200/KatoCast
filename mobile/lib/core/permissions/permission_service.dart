import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../error/exceptions.dart';

/// Tập trung xử lý quyền: vị trí (geolocator) + thông báo (permission_handler).
///
/// Trả kết quả rõ ràng để UI/repository xử lý mượt khi người dùng từ chối,
/// thay vì để app crash.
class PermissionService {
  /// Đảm bảo có quyền vị trí. Ném [LocationPermissionException] nếu không được.
  Future<void> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationPermissionException(
        'Dịch vụ định vị đang tắt. Hãy bật GPS trong cài đặt thiết bị.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Bạn đã từ chối quyền vị trí. Hãy cấp lại trong Cài đặt ứng dụng.',
        permanentlyDenied: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionException(
        'App cần quyền vị trí để dự báo thời tiết tại chỗ bạn đứng.',
      );
    }
  }

  /// Quyền vị trí đã ở mức "LUÔN CHO PHÉP" (background location) chưa?
  ///
  /// Quan trọng hơn nó nghe: [ensureLocationPermission] chỉ xin được mức "khi
  /// đang dùng app". Với mức đó, các isolate NỀN (alarm / foreground service /
  /// WorkManager) **không xin được toạ độ mới**, nên chúng phải dùng lại toạ độ
  /// đã lưu từ lần mở app gần nhất — nghĩa là bạn di chuyển mà app vẫn báo thời
  /// tiết của chỗ CŨ. Đây là nguyên nhân đã xác nhận trong nhật ký ("hệ thống
  /// không có last-known → thử toạ độ đã lưu" lặp lại mọi chu kỳ).
  Future<bool> hasBackgroundLocation() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Xin quyền vị trí nền ("Luôn cho phép").
  ///
  /// Android yêu cầu xin mức foreground TRƯỚC, và từ Android 11 thì lời xin nền
  /// KHÔNG hiện hộp thoại mà mở trang cài đặt hệ thống — nên hàm này fallback mở
  /// cài đặt app khi không được cấp trực tiếp.
  Future<bool> requestBackgroundLocation() async {
    try {
      // Bắt buộc có foreground trước, nếu không hệ thống từ chối thẳng.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always) return true;

      final status = await ph.Permission.locationAlways.request();
      if (status.isGranted) return true;
      // Android 11+: phải tự chọn "Luôn cho phép" trong cài đặt.
      await ph.openAppSettings();
      return await hasBackgroundLocation();
    } catch (_) {
      return false;
    }
  }

  /// Xin quyền thông báo (Android 13+/iOS). Trả false nếu bị từ chối — app
  /// vẫn chạy, chỉ là không gửi được alert.
  Future<bool> requestNotificationPermission() async {
    final status = await ph.Permission.notification.request();
    return status.isGranted;
  }

  /// Kiểm tra hiện đã có quyền thông báo chưa (cho UI Settings hiển thị).
  Future<bool> isNotificationGranted() async {
    return ph.Permission.notification.isGranted;
  }

  /// Xin tắt tối ưu hóa pin (whitelist) để background task chạy ổn định.
  /// Trả true nếu đã được whitelist.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    final status = await ph.Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// App đã được bỏ giới hạn pin (whitelist) chưa — để quyết định có nhắc lại
  /// không. Trả false nếu chưa hoặc không xác định được.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await ph.Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Thiết bị có cho đặt báo thức CHÍNH XÁC không (Android 12+/API 31+ mới cần).
  /// Bản tin hằng ngày cần quyền này để nổ đúng mốc giờ; thiếu → chỉ nổ gần
  /// đúng (inexact). Trả true khi được cấp hoặc nền tảng không áp dụng.
  Future<bool> isExactAlarmGranted() async {
    try {
      return await ph.Permission.scheduleExactAlarm.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Xin quyền đặt báo thức chính xác (mở màn cài đặt hệ thống trên Android
  /// 12+). Trả true nếu được cấp.
  Future<bool> requestExactAlarmPermission() async {
    try {
      final status = await ph.Permission.scheduleExactAlarm.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Kênh native mở trang cài đặt riêng của hãng (MainActivity.kt).
  static const _oemChannel = MethodChannel('katocast/oem');

  /// Mở trang "Tự khởi động / Autostart" của hãng để app sống sót khi vuốt tắt
  /// trên OEM diệt tiến trình mạnh (Nubia/MyOS, Xiaomi, Oppo…). Nếu không tìm
  /// được trang hãng → fallback mở trang App Info tiêu chuẩn để người dùng tự
  /// tìm mục Tự khởi động / Pin.
  Future<void> openAutoStartSettings() async {
    try {
      final ok = await _oemChannel.invokeMethod<bool>('openAutoStart');
      if (ok == true) return;
    } catch (_) {
      // Không có kênh/không hỗ trợ → fallback bên dưới.
    }
    await openSettings();
  }

  /// Mở màn hình cài đặt app (khi quyền bị từ chối vĩnh viễn).
  Future<void> openSettings() => Geolocator.openAppSettings();
}
