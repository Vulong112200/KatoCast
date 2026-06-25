import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wrapper quanh flutter_local_notifications.
///
/// Dùng cả ở foreground (khi mở app) lẫn trong background isolate
/// (WorkManager). Vì background isolate KHÔNG chia sẻ instance với main
/// isolate, mỗi nơi tự gọi [init] trước khi [show].
class NotificationService {
  static const String _channelId = 'weather_alerts';
  static const String _channelName = 'Cảnh báo thời tiết';
  static const String _channelDesc =
      'Thông báo chủ động về mưa và thay đổi thời tiết quanh bạn.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(initSettings);

    // Tạo channel (Android 8+). Importance high để hiện heads-up.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Hiện 1 thông báo ngay. [id] cố định theo loại để cập nhật thay vì spam.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details);
  }
}

/// ID thông báo cố định theo loại — gửi lại cùng ID sẽ thay thế notification cũ
/// (chống chồng chất nhiều cảnh báo mưa).
class NotificationIds {
  static const int rainStart = 1001;
  static const int rainStop = 1002;
  static const int envChange = 1003;
  static const int condition = 1004;
}
