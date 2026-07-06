import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/digest_scheduler.dart';
import '../../data/notification_prefs_store.dart';

/// Quản lý + lưu trữ cài đặt "Bản tin hằng ngày". Đọc 1 lần lúc khởi tạo, ghi
/// mỗi khi đổi. Lưu qua [NotificationPrefsStore] (dùng chung với background).
/// Mỗi lần đổi cài đặt → lập lịch lại bản tin (qua alarm hệ thống) để áp dụng
/// giờ/bật-tắt mới ngay.
class NotificationSettingsController extends StateNotifier<DigestPrefs> {
  NotificationSettingsController(this._store)
      : super(DigestPrefs.defaults()) {
    _load();
  }

  final NotificationPrefsStore _store;

  Future<void> _load() async {
    state = await _store.read();
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await _store.setEnabled(value);
    await _reschedule();
  }

  /// Thêm một mốc giờ mới (bỏ qua nếu trùng — normalizeTimes tự loại).
  Future<void> addTime(TimeOfDay time) async {
    final minutes = time.hour * 60 + time.minute;
    await _setTimes([...state.times, minutes]);
  }

  /// Xóa mốc giờ ở [index] (theo thứ tự đang hiển thị = đã sort).
  Future<void> removeTime(int index) async {
    if (index < 0 || index >= state.times.length) return;
    final next = [...state.times]..removeAt(index);
    await _setTimes(next);
  }

  /// Đổi giờ của mốc ở [index] sang [time].
  Future<void> updateTime(int index, TimeOfDay time) async {
    if (index < 0 || index >= state.times.length) return;
    final minutes = time.hour * 60 + time.minute;
    final next = [...state.times]..[index] = minutes;
    await _setTimes(next);
  }

  Future<void> _setTimes(List<int> minutes) async {
    state = state.copyWith(times: minutes); // copyWith tự sort + dedupe
    await _store.setTimes(state.times);
    await _reschedule();
  }

  /// Lập lịch lại alarm theo cài đặt mới. Nội dung không bake ở đây — callback
  /// alarm tự fetch tươi lúc bắn.
  Future<void> _reschedule() async {
    await scheduleDigests(state);
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsController, DigestPrefs>(
  (ref) => NotificationSettingsController(NotificationPrefsStore()),
);

/// Tiện ích đổi phút-trong-ngày sang [TimeOfDay] để hiển thị / time picker.
TimeOfDay minutesToTimeOfDay(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
