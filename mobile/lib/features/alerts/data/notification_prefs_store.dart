import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';

/// Hai mốc bản tin hằng ngày: buổi sáng & buổi chiều.
enum DigestSlot { morning, evening }

/// Cài đặt "Bản tin hằng ngày" — giờ lưu dưới dạng phút-trong-ngày (0..1439)
/// để biểu diễn `TimeOfDay` đơn giản, không phụ thuộc Flutter (dùng được ở
/// background isolate).
class DigestPrefs {
  /// Bật/tắt toàn bộ bản tin hằng ngày.
  final bool enabled;

  /// Mốc giờ buổi sáng (phút-trong-ngày), mặc định 6:30.
  final int morningMinutes;

  /// Mốc giờ buổi chiều (phút-trong-ngày), mặc định 16:30.
  final int eveningMinutes;

  const DigestPrefs({
    required this.enabled,
    required this.morningMinutes,
    required this.eveningMinutes,
  });

  const DigestPrefs.defaults()
      : enabled = true,
        morningMinutes = AppConfig.digestDefaultMorningMinutes,
        eveningMinutes = AppConfig.digestDefaultEveningMinutes;

  DigestPrefs copyWith({
    bool? enabled,
    int? morningMinutes,
    int? eveningMinutes,
  }) {
    return DigestPrefs(
      enabled: enabled ?? this.enabled,
      morningMinutes: morningMinutes ?? this.morningMinutes,
      eveningMinutes: eveningMinutes ?? this.eveningMinutes,
    );
  }

  int minutesOf(DigestSlot slot) =>
      slot == DigestSlot.morning ? morningMinutes : eveningMinutes;
}

/// Lưu cài đặt bản tin + theo dõi "đã gửi hôm nay" (SharedPreferences).
///
/// Class thuần, dùng chung cho cả background isolate (WorkManager) lẫn provider
/// Riverpod ở UI. Background isolate KHÔNG chia sẻ state nên đọc thẳng prefs.
class NotificationPrefsStore {
  static const _kEnabled = 'digest_enabled';
  static const _kMorning = 'digest_morning_min';
  static const _kEvening = 'digest_evening_min';
  static const _kSentMorning = 'digest_sent_morning';
  static const _kSentEvening = 'digest_sent_evening';

  Future<DigestPrefs> read() async {
    final prefs = await SharedPreferences.getInstance();
    return DigestPrefs(
      enabled: prefs.getBool(_kEnabled) ?? true,
      morningMinutes:
          prefs.getInt(_kMorning) ?? AppConfig.digestDefaultMorningMinutes,
      eveningMinutes:
          prefs.getInt(_kEvening) ?? AppConfig.digestDefaultEveningMinutes,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  Future<void> setMorning(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMorning, minutes);
  }

  Future<void> setEvening(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kEvening, minutes);
  }

  /// Mã ngày (yyyymmdd) bản tin của [slot] đã được gửi gần nhất; null nếu chưa.
  Future<int?> lastSentDay(DigestSlot slot) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyForSent(slot));
  }

  /// Ghi nhận đã gửi bản tin [slot] cho ngày [yyyymmdd] (chống gửi lặp).
  Future<void> markSent(DigestSlot slot, int yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyForSent(slot), yyyymmdd);
  }

  static String _keyForSent(DigestSlot slot) =>
      slot == DigestSlot.morning ? _kSentMorning : _kSentEvening;
}
