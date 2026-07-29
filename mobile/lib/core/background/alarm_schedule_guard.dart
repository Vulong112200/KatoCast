import 'package:shared_preferences/shared_preferences.dart';

/// Các guard dùng chung khi lập lịch alarm "mỗi ngày một mốc" (bản tin hằng ngày
/// và poll tin mới). Trước đây chỉ bản tin có các guard này; poll tin thì
/// `cancel` + đặt lại ở MỌI chu kỳ nền nên dễ bị đua giữa các isolate → lịch bị
/// mất hoặc tin bị báo lại. Gom về một chỗ để hai đường dùng đúng cùng logic.
class AlarmScheduleGuard {
  const AlarmScheduleGuard._();

  /// Khoảng throttle self-heal mặc định: các lời gọi NỀN (tick FG mỗi chu kỳ)
  /// không lập lại lịch thường xuyên hơn mức này — vừa tránh ANR (burst binder
  /// call) vừa tránh race hủy-rồi-đặt-lại clobber mốc sắp nổ.
  static const Duration defaultThrottle = Duration(hours: 1);

  /// Cửa sổ "vừa qua": mốc hôm nay đã trôi qua trong khoảng này thì KHÔNG đụng
  /// vào alarm của mốc đó — để callback của chính nó tự re-arm cho ngày mai,
  /// tránh dời nhầm mốc sáng sang hôm sau.
  static const Duration justPassedGrace = Duration(minutes: 20);

  /// Đã tới lúc được lập lại lịch chưa?
  ///
  /// [force] = true khi người dùng chủ động (mở app / đổi cài đặt) → luôn cho
  /// qua và ghi lại mốc. Trả false nghĩa là người gọi nên bỏ lượt self-heal này.
  ///
  /// `reload()` là bắt buộc: mỗi isolate giữ một bản cache SharedPreferences
  /// riêng, không reload thì isolate sống lâu (foreground service) sẽ không thấy
  /// mốc do isolate alarm ghi và cứ lập lại lịch mỗi chu kỳ.
  static Future<bool> claimSchedule(
    String prefsKey, {
    bool force = false,
    Duration throttle = defaultThrottle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      final lastMs = prefs.getInt(prefsKey) ?? 0;
      if (lastMs != 0 && nowMs - lastMs < throttle.inMilliseconds) return false;
    }
    await prefs.setInt(prefsKey, nowMs);
    return true;
  }

  /// Mốc [minutesOfDay] của hôm nay có vừa trôi qua trong [justPassedGrace]?
  static bool justPassed(DateTime now, int minutesOfDay) {
    final target = DateTime(
      now.year,
      now.month,
      now.day,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
    final diff = now.difference(target);
    return !diff.isNegative && diff <= justPassedGrace;
  }

  /// Mốc kế tiếp của [minutesOfDay] theo giờ địa phương; hôm nay đã qua thì lùi
  /// sang ngày mai.
  static DateTime nextInstanceOf(int minutesOfDay, {DateTime? from}) {
    final now = from ?? DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
