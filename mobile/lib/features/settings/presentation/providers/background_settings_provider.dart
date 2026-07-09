import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/background/background_prefs.dart';
import '../../../../core/background/background_triggers.dart';
import '../../../../core/config/app_config.dart';

/// Trạng thái cài đặt chạy nền: bật/tắt foreground service + chu kỳ cập nhật.
class BackgroundSettings {
  final bool foregroundEnabled;
  final int intervalMinutes;
  final bool activeAllDay;
  final int activeStartMinutes;
  final int activeEndMinutes;

  const BackgroundSettings({
    required this.foregroundEnabled,
    required this.intervalMinutes,
    required this.activeAllDay,
    required this.activeStartMinutes,
    required this.activeEndMinutes,
  });

  BackgroundSettings copyWith({
    bool? foregroundEnabled,
    int? intervalMinutes,
    bool? activeAllDay,
    int? activeStartMinutes,
    int? activeEndMinutes,
  }) {
    return BackgroundSettings(
      foregroundEnabled: foregroundEnabled ?? this.foregroundEnabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      activeAllDay: activeAllDay ?? this.activeAllDay,
      activeStartMinutes: activeStartMinutes ?? this.activeStartMinutes,
      activeEndMinutes: activeEndMinutes ?? this.activeEndMinutes,
    );
  }
}

/// Quản lý cài đặt chạy nền. Mỗi lần đổi → lưu prefs rồi gọi
/// `applyBackgroundTriggers` để áp dụng ngay (đảm bảo chỉ 1 lớp trigger chạy).
class BackgroundSettingsController extends StateNotifier<BackgroundSettings> {
  BackgroundSettingsController(this._store)
      : super(const BackgroundSettings(
          foregroundEnabled: true,
          intervalMinutes: AppConfig.backgroundIntervalMinutes,
          activeAllDay: AppConfig.activeHoursAllDayDefault,
          activeStartMinutes: AppConfig.activeHoursStartDefault,
          activeEndMinutes: AppConfig.activeHoursEndDefault,
        )) {
    _load();
  }

  final BackgroundPrefsStore _store;

  Future<void> _load() async {
    state = BackgroundSettings(
      foregroundEnabled: await _store.foregroundEnabled(),
      intervalMinutes: await _store.intervalMinutes(),
      activeAllDay: await _store.activeAllDay(),
      activeStartMinutes: await _store.activeStartMinutes(),
      activeEndMinutes: await _store.activeEndMinutes(),
    );
  }

  Future<void> setForegroundEnabled(bool value) async {
    state = state.copyWith(foregroundEnabled: value);
    await _store.setForegroundEnabled(value);
    await applyBackgroundTriggers();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    state = state.copyWith(intervalMinutes: minutes);
    await _store.setIntervalMinutes(minutes);
    // Áp chu kỳ mới: restart foreground service / re-arm alarm với interval mới.
    await applyBackgroundTriggers();
  }

  Future<void> setActiveAllDay(bool value) async {
    state = state.copyWith(activeAllDay: value);
    await _store.setActiveAllDay(value);
    // Re-arm để alarm backstop neo lại mốc kế tiếp theo khung mới ngay.
    await applyBackgroundTriggers();
  }

  Future<void> setActiveStartMinutes(int minutes) async {
    state = state.copyWith(activeStartMinutes: minutes);
    await _store.setActiveStartMinutes(minutes);
    await applyBackgroundTriggers();
  }

  Future<void> setActiveEndMinutes(int minutes) async {
    state = state.copyWith(activeEndMinutes: minutes);
    await _store.setActiveEndMinutes(minutes);
    await applyBackgroundTriggers();
  }
}

final backgroundSettingsProvider =
    StateNotifierProvider<BackgroundSettingsController, BackgroundSettings>(
  (ref) => BackgroundSettingsController(BackgroundPrefsStore()),
);
