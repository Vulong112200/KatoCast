import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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
    await _plugin.show(id, title, body, _details(title, body));
  }

  /// Lập lịch bản tin lặp HẰNG NGÀY vào [hour]:[minute] (giờ địa phương).
  ///
  /// Dùng alarm hệ thống (đáng tin hơn WorkManager cho mốc giờ cố định):
  /// `inexactAllowWhileIdle` bắn được cả trong Doze và KHÔNG cần quyền
  /// SCHEDULE_EXACT_ALARM. [matchDateTimeComponents]=time để lặp mỗi ngày.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOf(hour, minute),
      _details(title, body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Huỷ một thông báo / lịch theo [id].
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  /// Cấu hình hiển thị dùng chung — BigTextStyle để body dài KHÔNG bị cắt
  /// (mở rộng hiển thị đầy đủ % mưa, giờ mưa, lời khuyên…).
  NotificationDetails _details(String title, String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// Mốc kế tiếp của [hour]:[minute] trong múi giờ địa phương. Nếu hôm nay đã
  /// qua thì lùi sang ngày mai.
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

/// ID thông báo cố định theo loại — gửi lại cùng ID sẽ thay thế notification cũ
/// (chống chồng chất nhiều cảnh báo mưa).
class NotificationIds {
  static const int rainStart = 1001;
  static const int rainStop = 1002;
  static const int envChange = 1003;
  static const int condition = 1004;

  /// Bản tin thời tiết hằng ngày — mỗi mốc (sáng/chiều) một ID riêng vì cả hai
  /// được lập lịch song song qua zonedSchedule (chung ID sẽ ghi đè nhau).
  static const int dailyDigestMorning = 1005;
  static const int dailyDigestEvening = 1006;
}
