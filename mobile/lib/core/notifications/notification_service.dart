import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_response_handler.dart';

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

  /// Channel ghi chú GHIM (sticky): im lặng (low) — không heads-up mỗi lần
  /// re-assert; notification vẫn hiện cố định trên khay.
  static const String notePinnedChannelId = 'note_pinned';

  /// Channel NHẮC ghi chú theo lịch: high để heads-up đúng giờ hẹn.
  static const String noteReminderChannelId = 'note_reminders';

  /// Channel THÔNG BÁO thông tin mới (JLPT/MBA…): high để heads-up khi có tin.
  static const String announcementsChannelId = 'announcements';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    // Callbacks: chạm thân notification (main isolate) + nút action chạy nền
    // (isolate riêng — cần ActionBroadcastReceiver trong AndroidManifest).
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: onNotificationActionBackground,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Tạo channel (Android 8+). Importance high để hiện heads-up.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await android?.createNotificationChannel(channel);
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      notePinnedChannelId,
      'Ghi chú ghim',
      description: 'Ghi chú được ghim cố định trên thanh thông báo.',
      importance: Importance.low,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      noteReminderChannelId,
      'Nhắc ghi chú',
      description: 'Thông báo nhắc ghi chú theo lịch bạn đặt.',
      importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      announcementsChannelId,
      'Thông báo mới',
      description: 'Tin mới về kỳ thi (JLPT), khoá học (MBA) và chủ đề bạn theo dõi.',
      importance: Importance.high,
    ));

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

  /// Hiện thông báo tin mới (JLPT/MBA…) trên channel [announcementsChannelId],
  /// BigText để tiêu đề + nguồn dài không bị cắt. [payload] để tap điều hướng.
  Future<void> showAnnouncement({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        announcementsChannelId,
        'Thông báo mới',
        channelDescription:
            'Tin mới về kỳ thi (JLPT), khoá học (MBA) và chủ đề bạn theo dõi.',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Huỷ một thông báo / lịch theo [id].
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  /// Hiện notification với [details] tuỳ biến (ghi chú ghim: ongoing + action).
  Future<void> showWithDetails({
    required int id,
    String? title,
    String? body,
    required NotificationDetails details,
    String? payload,
  }) async {
    await init();
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Lập lịch notification với [details] tuỳ biến (nhắc ghi chú).
  ///
  /// [matchDateTimeComponents]: null = một lần; `time` = lặp hằng ngày;
  /// `dayOfWeekAndTime` = lặp hằng tuần đúng thứ.
  Future<void> zonedScheduleWithDetails({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exactAllowWhileIdle,
  }) async {
    await init();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      payload: payload,
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  /// App có được mở từ một notification không (cold launch) — dùng để điều
  /// hướng tới màn liên quan (vd ghi chú) ngay khi khởi động.
  Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    await init();
    return _plugin.getNotificationAppLaunchDetails();
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

  /// Bản tin thời tiết hằng ngày (mô hình CŨ 2 mốc) — chỉ giữ để hủy khi migrate
  /// sang dải động [digestBase]. Không dùng để lập lịch mới nữa.
  static const int dailyDigestMorning = 1005;
  static const int dailyDigestEvening = 1006;

  /// Bản tin thời tiết hằng ngày — dải ID động cho danh sách nhiều mốc tùy ý.
  /// Mốc thứ `i` (index trong danh sách đã sort) → ID `digestBase + i`. Dải
  /// [1100, 1100 + AppConfig.digestMaxSlots) nằm dưới dải ghi chú (10000+) nên
  /// không đụng. Số mốc tối đa xem `AppConfig.digestMaxSlots`.
  static const int digestBase = 1100;

  /// Bản tin THỬ (tự chẩn đoán chạy nền). Nằm DƯỚI `digestBase` nên khi callback
  /// tính `index = id - digestBase < 0` → không re-arm (bắn đúng một lần).
  static const int digestTest = 1099;

  /// Thông báo tin mới (JLPT/MBA…). Alarm poll dùng [announcementAlarm]; mỗi tin
  /// hiển thị với ID `announcementBase + (remoteId % announcementIdSpan)` để
  /// nhiều tin không đè nhau. Dải [2000, 2000+span) nằm giữa weather/digest và
  /// notes (10000+) nên không đụng.
  static const int announcementAlarm = 1200;
  static const int announcementBase = 2000;
  static const int announcementIdSpan = 500;
}
