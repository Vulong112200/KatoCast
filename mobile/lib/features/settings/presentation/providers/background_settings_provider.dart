import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/background/background_prefs.dart';
import '../../../../core/background/background_triggers.dart';
import '../../../../core/config/app_config.dart';

/// Trạng thái cài đặt chạy nền: bật/tắt foreground service + chu kỳ cập nhật.
class BackgroundSettings {
  final bool foregroundEnabled;
  final int intervalMinutes;

  const BackgroundSettings({
    required this.foregroundEnabled,
    required this.intervalMinutes,
  });

  BackgroundSettings copyWith({bool? foregroundEnabled, int? intervalMinutes}) {
    return BackgroundSettings(
      foregroundEnabled: foregroundEnabled ?? this.foregroundEnabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
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
        )) {
    _load();
  }

  final BackgroundPrefsStore _store;

  Future<void> _load() async {
    state = BackgroundSettings(
      foregroundEnabled: await _store.foregroundEnabled(),
      intervalMinutes: await _store.intervalMinutes(),
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
}

final backgroundSettingsProvider =
    StateNotifierProvider<BackgroundSettingsController, BackgroundSettings>(
  (ref) => BackgroundSettingsController(BackgroundPrefsStore()),
);
