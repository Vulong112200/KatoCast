import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';

/// Cài đặt "Bản tin hằng ngày" — danh sách nhiều mốc giờ tùy ý.
///
/// Giờ lưu dưới dạng phút-trong-ngày (0..1439) để biểu diễn `TimeOfDay` đơn
/// giản, không phụ thuộc Flutter (dùng được ở background isolate). [times] luôn
/// được giữ đã SORT tăng dần và loại trùng.
class DigestPrefs {
  /// Bật/tắt toàn bộ bản tin hằng ngày.
  final bool enabled;

  /// Danh sách mốc giờ (phút-trong-ngày), sorted + không trùng.
  final List<int> times;

  const DigestPrefs({
    required this.enabled,
    required this.times,
  });

  DigestPrefs.defaults()
      : enabled = true,
        times = List<int>.from(AppConfig.digestDefaultTimes);

  DigestPrefs copyWith({
    bool? enabled,
    List<int>? times,
  }) {
    return DigestPrefs(
      enabled: enabled ?? this.enabled,
      times: times != null ? normalizeTimes(times) : this.times,
    );
  }

  /// Sort tăng dần + loại trùng + kẹp trong dải hợp lệ [0,1439] + giới hạn số
  /// lượng theo [AppConfig.digestMaxSlots].
  static List<int> normalizeTimes(List<int> input) {
    final set = <int>{
      for (final m in input)
        if (m >= 0 && m <= 1439) m,
    };
    final list = set.toList()..sort();
    if (list.length > AppConfig.digestMaxSlots) {
      return list.sublist(0, AppConfig.digestMaxSlots);
    }
    return list;
  }
}

/// Lưu cài đặt bản tin (SharedPreferences).
///
/// Class thuần, dùng chung cho cả background isolate (WorkManager) lẫn provider
/// Riverpod ở UI. Background isolate KHÔNG chia sẻ state nên đọc thẳng prefs.
class NotificationPrefsStore {
  static const _kEnabled = 'digest_enabled';
  static const _kTimes = 'digest_times';

  // Key CŨ (mô hình 2 mốc sáng/chiều) — chỉ đọc để migrate sang [_kTimes].
  static const _kLegacyMorning = 'digest_morning_min';
  static const _kLegacyEvening = 'digest_evening_min';

  Future<DigestPrefs> read() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? true;

    final stored = prefs.getStringList(_kTimes);
    if (stored != null) {
      final times = DigestPrefs.normalizeTimes(
        stored.map(int.tryParse).whereType<int>().toList(),
      );
      // Nếu list rỗng bất thường, rơi về mặc định để không mất bản tin.
      return DigestPrefs(
        enabled: enabled,
        times: times.isEmpty
            ? List<int>.from(AppConfig.digestDefaultTimes)
            : times,
      );
    }

    // Chưa có key mới → migrate từ 2 key cũ nếu tồn tại, ngược lại mặc định.
    final legacy = <int>[
      if (prefs.containsKey(_kLegacyMorning)) prefs.getInt(_kLegacyMorning)!,
      if (prefs.containsKey(_kLegacyEvening)) prefs.getInt(_kLegacyEvening)!,
    ];
    final times = legacy.isNotEmpty
        ? DigestPrefs.normalizeTimes(legacy)
        : List<int>.from(AppConfig.digestDefaultTimes);
    // Ghi lại theo mô hình mới để lần sau khỏi migrate.
    await prefs.setStringList(_kTimes, times.map((m) => '$m').toList());
    return DigestPrefs(enabled: enabled, times: times);
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  Future<void> setTimes(List<int> minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final times = DigestPrefs.normalizeTimes(minutes);
    await prefs.setStringList(_kTimes, times.map((m) => '$m').toList());
  }
}
