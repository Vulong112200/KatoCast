import 'log_entry.dart';
import 'log_tags.dart';

/// Bản tóm tắt "app có đang chạy không" — SUY RA từ chính các dòng nhật ký, nên
/// không cần thêm một nơi lưu trạng thái thứ hai (một nguồn sự thật duy nhất).
class LogHealth {
  /// Lần vào chu kỳ nền gần nhất (bất kể lớp nào).
  final DateTime? lastCycleAt;

  /// Nguồn của chu kỳ gần nhất (xem [LogSource]).
  final String? lastCycleSource;

  /// Lần lấy dữ liệu THÀNH CÔNG gần nhất (gọi API ok, không phải cache fallback).
  final DateTime? lastFetchOkAt;

  /// Lần hiển thị thông báo gần nhất.
  final DateTime? lastNotifyAt;

  /// Lỗi gần nhất + nội dung để hiện ngay trên thẻ Tình trạng.
  final DateTime? lastErrorAt;
  final String? lastErrorMessage;

  /// Mốc alarm kế tiếp đã đặt (đọc từ dòng `arm` gần nhất của alarm chính).
  final DateTime? nextAlarmAt;

  /// Thống kê 24h qua.
  final int cycles24h;
  final int fetches24h;
  final int notifies24h;
  final int errors24h;

  /// Số lượt bị bỏ vì chu kỳ khác đang chạy (lock) — cho thấy chống chạy chồng
  /// đang có tác dụng.
  final int lockSkips24h;

  /// Khoảng trống DÀI NHẤT giữa hai chu kỳ trong 24h qua. Đây là con số quan
  /// trọng nhất để phát hiện "app ngủ mất mấy tiếng" (vd đêm qua đứt 8 tiếng).
  final Duration? longestGap24h;

  const LogHealth({
    this.lastCycleAt,
    this.lastCycleSource,
    this.lastFetchOkAt,
    this.lastNotifyAt,
    this.lastErrorAt,
    this.lastErrorMessage,
    this.nextAlarmAt,
    this.cycles24h = 0,
    this.fetches24h = 0,
    this.notifies24h = 0,
    this.errors24h = 0,
    this.lockSkips24h = 0,
    this.longestGap24h,
  });

  /// Dựng từ danh sách nhật ký (MỚI NHẤT TRƯỚC — đúng thứ tự `AppLog.readAll`).
  factory LogHealth.from(List<LogEntry> entries, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final since = ref.subtract(const Duration(hours: 24));

    DateTime? lastCycleAt;
    String? lastCycleSource;
    DateTime? lastFetchOkAt;
    DateTime? lastNotifyAt;
    DateTime? lastErrorAt;
    String? lastErrorMessage;
    DateTime? nextAlarmAt;
    var cycles = 0, fetches = 0, notifies = 0, errors = 0, lockSkips = 0;
    final cycleTimes = <DateTime>[];
    // App có chạy chu kỳ nào TRƯỚC cửa sổ 24h không? Nếu KHÔNG (mới cài, vừa xoá
    // nhật ký) thì đoạn đầu cửa sổ chưa từng được quan sát — coi nó là "khoảng
    // ngủ" sẽ báo động giả một khoảng đứt to tướng.
    var hadCycleBeforeWindow = false;

    for (final e in entries) {
      final recent = !e.ts.isBefore(since);
      switch (e.tag) {
        case LogTags.cycle:
          lastCycleAt ??= e.ts;
          lastCycleSource ??= e.source;
          if (recent) {
            cycles++;
            cycleTimes.add(e.ts);
          } else {
            hadCycleBeforeWindow = true;
          }
        case LogTags.fetch:
          if (e.level == LogLevel.info) {
            lastFetchOkAt ??= e.ts;
            if (recent) fetches++;
          }
        case LogTags.notify:
          lastNotifyAt ??= e.ts;
          if (recent) notifies++;
        case LogTags.arm:
          // Chỉ tin mốc của alarm CHÍNH (bỏ digest/announce/heartbeat) để con số
          // "alarm kế tiếp" đúng nghĩa "lần cập nhật thời tiết kế tiếp".
          if (nextAlarmAt == null && e.source == LogSource.alarm) {
            final at = e.data['at'];
            if (at is int) nextAlarmAt = DateTime.fromMillisecondsSinceEpoch(at);
          }
        case LogTags.lock:
          if (recent) lockSkips++;
      }
      if (e.level == LogLevel.error) {
        lastErrorAt ??= e.ts;
        lastErrorMessage ??= e.data['err']?.toString() ?? e.message;
        if (recent) errors++;
      }
    }

    return LogHealth(
      lastCycleAt: lastCycleAt,
      lastCycleSource: lastCycleSource,
      lastFetchOkAt: lastFetchOkAt,
      lastNotifyAt: lastNotifyAt,
      lastErrorAt: lastErrorAt,
      lastErrorMessage: lastErrorMessage,
      nextAlarmAt: nextAlarmAt,
      cycles24h: cycles,
      fetches24h: fetches,
      notifies24h: notifies,
      errors24h: errors,
      lockSkips24h: lockSkips,
      longestGap24h: _longestGap(
        cycleTimes,
        ref,
        hadCycleBeforeWindow ? since : null,
      ),
    );
  }

  /// Khoảng trống dài nhất giữa các chu kỳ. [times] theo thứ tự GIẢM dần.
  ///
  /// Tính cả đoạn từ chu kỳ gần nhất tới [ref] (app đang ngủ ngay lúc này). Đoạn
  /// từ đầu cửa sổ tới chu kỳ cũ nhất CHỈ tính khi [windowStart] khác null —
  /// nghĩa là đã biết app có chạy trước cửa sổ, nên đoạn im lặng đó là thật. Nếu
  /// nhật ký chưa trải hết 24h (mới cài / vừa xoá) thì bỏ, tránh báo động giả.
  static Duration? _longestGap(
    List<DateTime> times,
    DateTime ref,
    DateTime? windowStart,
  ) {
    if (times.isEmpty) return null;
    var longest = ref.difference(times.first);
    for (var i = 0; i < times.length - 1; i++) {
      final gap = times[i].difference(times[i + 1]);
      if (gap > longest) longest = gap;
    }
    if (windowStart != null) {
      final tail = times.last.difference(windowStart);
      if (tail > longest) longest = tail;
    }
    return longest.isNegative ? Duration.zero : longest;
  }
}
