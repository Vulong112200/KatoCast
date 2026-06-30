import '../../../core/notifications/notification_service.dart';
import '../../weather/domain/entities/weather.dart';
import '../domain/usecases/build_daily_digest.dart';
import 'notification_prefs_store.dart';

/// Lập lịch (hoặc huỷ) hai bản tin hằng ngày qua alarm hệ thống.
///
/// Gọi mỗi khi: mở app, đổi cài đặt bản tin, hoặc worker nền fetch xong — để
/// nội dung bản tin luôn tươi nhất có thể tại thời điểm lập lịch. Dùng được cả
/// ở background isolate (thuần, chỉ phụ thuộc [NotificationService] + entity).
///
/// - `!prefs.enabled` → huỷ cả hai mốc.
/// - `data == null` (chưa có cache/dữ liệu) → bỏ qua, lần lập lịch sau sẽ điền.
Future<void> scheduleDigests(
  NotificationService notif,
  DigestPrefs prefs,
  WeatherData? data,
) async {
  if (!prefs.enabled) {
    await notif.cancel(NotificationIds.dailyDigestMorning);
    await notif.cancel(NotificationIds.dailyDigestEvening);
    return;
  }
  if (data == null) return;

  final digest = const BuildDailyDigest().call(data);

  await notif.scheduleDaily(
    id: NotificationIds.dailyDigestMorning,
    hour: prefs.morningMinutes ~/ 60,
    minute: prefs.morningMinutes % 60,
    title: digest.title,
    body: digest.body,
  );
  await notif.scheduleDaily(
    id: NotificationIds.dailyDigestEvening,
    hour: prefs.eveningMinutes ~/ 60,
    minute: prefs.eveningMinutes % 60,
    title: digest.title,
    body: digest.body,
  );
}
