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

  test('KHÔNG nhả lock của chủ MỚI sau khi mình bị chiếm lại (quá hạn)',
      () async {
    // Kịch bản thật: chu kỳ A treo quá staleAfter → B chiếm lại lock (đúng) →
    // A tỉnh lại và chạy `finally { release() }`. Bản cũ xoá vô điều kiện nên
    // xoá luôn lock của B, mở đường cho chu kỳ thứ ba chen vào giữa lúc B đang
    // mở DB — đúng loại tranh chấp mà lock này tồn tại để ngăn.
    // A (isolate này) chiếm lock.
    expect(await CycleLock.tryAcquire(LogSource.fg), isTrue);

    // B là một ISOLATE KHÁC nên nó có `_heldToken` static riêng — không mô phỏng
    // được bằng `tryAcquire` trong cùng test. Thay vào đó ghi thẳng file lock
    // với token của B, đúng như những gì B để lại trên đĩa sau khi chiếm lại.
    final lock = File('${tmp.path}/bg_cycle.lock');
    await lock.writeAsString(
        '${LogSource.worker}|${DateTime.now().millisecondsSinceEpoch}|token-cua-B');

    // A tỉnh lại và chạy `finally { release() }` → phải NHẬN RA lock không còn
    // là của mình và để nguyên.
    await CycleLock.release();
    expect(await lock.exists(), isTrue,
        reason: 'lock của chủ mới phải còn nguyên');
    expect((await lock.readAsString()), contains('token-cua-B'));
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

  // runWaiting dành cho bản tin & poll tin — việc mỗi ngày một lần mà người dùng
  // đang đợi. Bug thật: bản tin 6:30 nổ đúng lúc WorkManager giữ lock, bị
  // runGuarded bỏ lượt rồi tự hẹn lại NGÀY MAI → mất hẳn bản tin của ngày đó.
  group('runWaiting', () {
    test('lock rảnh ⇒ chạy ngay và nhả lock', () async {
      var ran = 0;
      final result = await CycleLock.runWaiting(LogSource.digest, () async {
        ran++;
        return 'ok';
      });
      expect(result, 'ok');
      expect(ran, 1);
      expect(await CycleLock.tryAcquire(LogSource.fg), isTrue);
      await CycleLock.release();
    });

    test('lock đang bị giữ ⇒ VẪN CHẠY sau khi hết thời gian chờ', () async {
      await CycleLock.tryAcquire(LogSource.worker);
      var ran = 0;
      final result = await CycleLock.runWaiting(
        LogSource.digest,
        () async {
          ran++;
          return 'đã gửi bản tin';
        },
        wait: const Duration(milliseconds: 10),
      );
      expect(ran, 1, reason: 'KHÔNG được bỏ bản tin chỉ vì lock đang bị giữ');
      expect(result, 'đã gửi bản tin');
      await CycleLock.release();
    });

    test('chạy bất chấp thì KHÔNG nhả lock của lớp khác', () async {
      await CycleLock.tryAcquire(LogSource.worker);
      await CycleLock.runWaiting(
        LogSource.digest,
        () async => null,
        wait: const Duration(milliseconds: 10),
      );
      // Lock vẫn thuộc `worker`; nếu runWaiting xoá nó thì một chu kỳ thứ ba sẽ
      // chen vào giữa lúc worker còn đang chạy.
      expect(await CycleLock.tryAcquire(LogSource.fg), isFalse);
      await CycleLock.release();
    });

    test('lock được nhả giữa lúc chờ ⇒ chiếm được và nhả lại sau khi xong',
        () async {
      await CycleLock.tryAcquire(LogSource.worker);
      // Nhả sau một nhịp thăm dò.
      Future<void>.delayed(const Duration(seconds: 4), CycleLock.release);

      var ran = 0;
      await CycleLock.runWaiting(
        LogSource.digest,
        () async => ran++,
        wait: const Duration(seconds: 20),
      );
      expect(ran, 1);
      // Đã chiếm được thật nên phải nhả → lượt sau vào được.
      expect(await CycleLock.tryAcquire(LogSource.fg), isTrue);
      await CycleLock.release();
    });

    test('action ném lỗi ⇒ vẫn nhả lock', () async {
      await expectLater(
        CycleLock.runWaiting(
          LogSource.digest,
          () async => throw StateError('lỗi giữa bản tin'),
        ),
        throwsStateError,
      );
      expect(await CycleLock.tryAcquire(LogSource.fg), isTrue,
          reason: 'lock phải được nhả trong finally');
      await CycleLock.release();
    });
  });
}
