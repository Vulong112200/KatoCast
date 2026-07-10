import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';

/// Cài đặt "Theo dõi thông báo": bật/tắt, mốc giờ kiểm tra mỗi ngày (phút-trong-
/// ngày), và các chủ đề đang theo dõi (khớp `topic` backend).
///
/// Thuần, không phụ thuộc Flutter → dùng được ở background isolate (alarm poll).
class AnnouncementPrefs {
  final bool enabled;
  final int checkMinutes; // phút-trong-ngày (0..1439)
  final List<String> topics;

  const AnnouncementPrefs({
    required this.enabled,
    required this.checkMinutes,
    required this.topics,
  });

  AnnouncementPrefs.defaults()
      : enabled = true,
        checkMinutes = AppConfig.announcementCheckDefaultMinutes,
        topics = List<String>.from(AppConfig.announcementTopics);

  AnnouncementPrefs copyWith({
    bool? enabled,
    int? checkMinutes,
    List<String>? topics,
  }) {
    return AnnouncementPrefs(
      enabled: enabled ?? this.enabled,
      checkMinutes: checkMinutes ?? this.checkMinutes,
      topics: topics ?? this.topics,
    );
  }
}

class AnnouncementPrefsStore {
  static const _kEnabled = 'ann_enabled';
  static const _kCheckMin = 'ann_check_min';
  static const _kTopics = 'ann_topics';

  Future<AnnouncementPrefs> read() async {
    final prefs = await SharedPreferences.getInstance();
    final topics = prefs.getStringList(_kTopics);
    return AnnouncementPrefs(
      enabled: prefs.getBool(_kEnabled) ?? true,
      checkMinutes:
          prefs.getInt(_kCheckMin) ?? AppConfig.announcementCheckDefaultMinutes,
      topics: (topics == null || topics.isEmpty)
          ? List<String>.from(AppConfig.announcementTopics)
          : topics,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  Future<void> setCheckMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCheckMin, minutes.clamp(0, 1439));
  }

  Future<void> setTopics(List<String> topics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTopics, topics);
  }
}
