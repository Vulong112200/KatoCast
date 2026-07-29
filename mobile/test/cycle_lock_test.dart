import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/background/cycle_lock.dart';
import 'package:katocast/core/diagnostics/app_log.dart';
import 'package:katocast/core/diagnostics/log_entry.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kato_lock_test');
    CycleLock.debugOverrideDirectory(tmp.path);
    // Nhật ký cũng vào thư mục tạm để CycleLock ghi log không đụng máy thật.
    AppLog.debugOverrideDirectory(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('chiếm được lock khi chưa ai giữ', () async {
    expect(await CycleLock.tryAcquire(LogSource.alarm), isTrue);
    await CycleLock.release();
  });

  test('CHẶN lượt thứ hai khi lock đang được giữ', () async {
    expect(await CycleLock.tryAcquire(LogSource.fg), isTrue);
    // Đây là ca thật gây thông báo trùng: alarm nổ đúng lúc foreground tick.
    expect(await CycleLock.tryAcquire(LogSource.alarm), isFalse);
    await CycleLock.release();
    // Sau khi nhả thì lượt sau vào được.
    expect(await CycleLock.tryAcquire(LogSource.alarm), isTrue);
    await CycleLock.release();
  });

  test('CHIẾM LẠI lock quá hạn (chủ cũ bị OEM giết giữa chu kỳ)', () async {
    // Mô phỏng lock bỏ hoang: chủ cũ ghi mốc rồi chết, không bao giờ release.
    final stale = DateTime.now()
        .subtract(CycleLock.staleAfter + const Duration(minutes: 1));
    await File('${tmp.path}/bg_cycle.lock')
        .writeAsString('${LogSource.fg}|${stale.millisecondsSinceEpoch}');

    expect(await CycleLock.tryAcquire(LogSource.alarm), isTrue,
        reason: 'lock quá hạn phải chiếm lại được, không thì app tự khoá chết');
    await CycleLock.release();
  });

  test('lock CHƯA quá hạn thì vẫn chặn', () async {
    final fresh = DateTime.now()
        .subtract(CycleLock.staleAfter - const Duration(seconds: 30));
    await File('${tmp.path}/bg_cycle.lock')
        .writeAsString('${LogSource.fg}|${fresh.millisecondsSinceEpoch}');

    expect(await CycleLock.tryAcquire(LogSource.alarm), isFalse);
  });

  test('file lock hỏng → coi như không có chủ, vẫn chạy được', () async {
    await File('${tmp.path}/bg_cycle.lock').writeAsString('rác không parse được');
    expect(await CycleLock.tryAcquire(LogSource.alarm), isTrue);
    await CycleLock.release();
  });

  test('release an toàn khi gọi lặp / chưa từng chiếm', () async {
    await CycleLock.release();
    await CycleLock.release();
    expect(await CycleLock.tryAcquire(LogSource.worker), isTrue);
    await CycleLock.release();
    await CycleLock.release();
  });

  group('runGuarded', () {
    test('chạy action và nhả lock sau khi xong', () async {
      var ran = 0;
      final result = await CycleLock.runGuarded(LogSource.alarm, () async {
        ran++;
        return 42;
      });
      expect(result, 42);
      expect(ran, 1);
      // Lock đã nhả → lượt sau vào được.
      expect(await CycleLock.tryAcquire(LogSource.fg), isTrue);
      await CycleLock.release();
    });

    test('trả null và KHÔNG chạy action khi bị chặn', () async {
      await CycleLock.tryAcquire(LogSource.fg);
      var ran = 0;
      final result = await CycleLock.runGuarded(LogSource.alarm, () async {
        ran++;
        return 42;
      });
      expect(result, isNull);
      expect(ran, 0, reason: 'không được chạy chu kỳ thứ hai song song');
      await CycleLock.release();
    });

    test('action ném lỗi thì vẫn nhả lock (không khoá chết chuỗi nền)', () async {
      await expectLater(
        CycleLock.runGuarded(
          LogSource.alarm,
          () async => throw StateError('lỗi giữa chu kỳ'),
        ),
        throwsStateError,
      );
      expect(await CycleLock.tryAcquire(LogSource.fg), isTrue,
          reason: 'lock phải được nhả trong finally');
      await CycleLock.release();
    });
  });
}
