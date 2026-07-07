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
