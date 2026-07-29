import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/background/background_prefs.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/diagnostics/app_log.dart';
import '../../../../core/diagnostics/log_entry.dart';
import '../../../../core/diagnostics/log_health.dart';
import '../../../../core/diagnostics/log_tags.dart';
import '../../../alerts/data/digest_scheduler.dart' show canScheduleExactAlarms;

/// Bộ lọc nhóm trên trang Nhật ký.
enum LogFilter {
  all,
  background,
  notifications,
  errors;

  String get label => switch (this) {
        LogFilter.all => 'Tất cả',
        LogFilter.background => 'Chạy nền',
        LogFilter.notifications => 'Thông báo',
        LogFilter.errors => 'Lỗi',
      };

  /// Dòng nhật ký này có thuộc nhóm đang lọc?
  bool matches(LogEntry e) => switch (this) {
        LogFilter.all => true,
        LogFilter.background =>
          LogSource.backgroundSources.contains(e.source) ||
              e.tag == LogTags.cycle ||
              e.tag == LogTags.arm,
        LogFilter.notifications =>
          e.tag == LogTags.notify || e.tag == LogTags.skip,
        LogFilter.errors => e.level == LogLevel.error || e.level == LogLevel.warn,
      };
}

/// Toàn bộ nhật ký (mới nhất trước). Đọc từ file JSONL nên rẻ và không phụ thuộc
/// DB — cố tình như vậy để đọc được cả những lỗi ở tầng DB.
final logEntriesProvider =
    FutureProvider.autoDispose<List<LogEntry>>((ref) => AppLog.readAll());

/// Tóm tắt tình trạng, suy ra từ chính các dòng nhật ký.
final logHealthProvider = FutureProvider.autoDispose<LogHealth>((ref) async {
  final entries = await ref.watch(logEntriesProvider.future);
  return LogHealth.from(entries);
});

/// Bộ lọc đang chọn.
final logFilterProvider = StateProvider.autoDispose<LogFilter>(
  (ref) => LogFilter.all,
);

/// Từ khoá tìm kiếm (khớp cả message, tag và nguồn).
final logSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Nhật ký sau khi áp bộ lọc + tìm kiếm.
final filteredLogEntriesProvider =
    FutureProvider.autoDispose<List<LogEntry>>((ref) async {
  final entries = await ref.watch(logEntriesProvider.future);
  final filter = ref.watch(logFilterProvider);
  final query = ref.watch(logSearchProvider).trim().toLowerCase();

  return entries.where((e) {
    if (!filter.matches(e)) return false;
    if (query.isEmpty) return true;
    return e.message.toLowerCase().contains(query) ||
        e.tag.toLowerCase().contains(query) ||
        e.source.toLowerCase().contains(query) ||
        e.data.entries.any((d) =>
            d.key.toLowerCase().contains(query) ||
            d.value.toString().toLowerCase().contains(query));
  }).toList();
});

/// Trạng thái môi trường của thiết bị — những điều kiện quyết định việc chạy nền
/// có sống được hay không. Gom vào một chỗ để người dùng tự đối chiếu.
class RuntimeStatus {
  final bool foregroundEnabled;
  final bool foregroundRunning;
  final bool exactAlarmGranted;
  final bool batteryUnrestricted;
  final int intervalMinutes;
  final bool activeAllDay;
  final int activeStartMinutes;
  final int activeEndMinutes;

  const RuntimeStatus({
    required this.foregroundEnabled,
    required this.foregroundRunning,
    required this.exactAlarmGranted,
    required this.batteryUnrestricted,
    required this.intervalMinutes,
    required this.activeAllDay,
    required this.activeStartMinutes,
    required this.activeEndMinutes,
  });
}

final runtimeStatusProvider =
    FutureProvider.autoDispose<RuntimeStatus>((ref) async {
  final prefs = BackgroundPrefsStore();
  final permission = ref.watch(permissionServiceProvider);

  var running = false;
  try {
    running = await FlutterForegroundTask.isRunningService;
  } catch (_) {
    // Nền tảng không hỗ trợ → coi như không chạy.
  }
  var battery = false;
  try {
    battery = await permission.isIgnoringBatteryOptimizations();
  } catch (_) {
    // Không truy vấn được → hiển thị "chưa rõ" phía UI qua giá trị false.
  }

  return RuntimeStatus(
    foregroundEnabled: await prefs.foregroundEnabled(),
    foregroundRunning: running,
    exactAlarmGranted: await canScheduleExactAlarms(),
    batteryUnrestricted: battery,
    intervalMinutes: await prefs.intervalMinutes(),
    activeAllDay: await prefs.activeAllDay(),
    activeStartMinutes: await prefs.activeStartMinutes(),
    activeEndMinutes: await prefs.activeEndMinutes(),
  );
});
