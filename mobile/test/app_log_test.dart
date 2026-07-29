import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/config/app_config.dart';
import 'package:katocast/core/diagnostics/app_log.dart';
import 'package:katocast/core/diagnostics/log_entry.dart';
import 'package:katocast/core/diagnostics/log_health.dart';
import 'package:katocast/core/diagnostics/log_tags.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kato_log_test');
    AppLog.debugOverrideDirectory(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('AppLog', () {
    test('ghi rồi đọc lại được, mới nhất trước', () async {
      await AppLog.i(LogSource.alarm, LogTags.cycle, 'chu kỳ 1');
      await AppLog.w(LogSource.fg, LogTags.window, 'ngoài khung');
      await AppLog.e(
        LogSource.worker,
        LogTags.db,
        'DB khoá',
        error: StateError('database is locked'),
      );
      await AppLog.flush();

      final entries = await AppLog.readAll();
      expect(entries.length, 3);
      // Mới nhất trước.
      expect(entries.first.message, 'DB khoá');
      expect(entries.first.level, LogLevel.error);
      expect(entries.first.data['err'], contains('database is locked'));
      expect(entries.last.message, 'chu kỳ 1');
    });

    test('data giữ nguyên và bỏ khoá null', () async {
      await AppLog.i(
        LogSource.alarm,
        LogTags.source,
        'dùng cache',
        data: {'tuổi': '14p', 'bỏ tôi': null},
      );
      await AppLog.flush();

      final entries = await AppLog.readAll();
      expect(entries.single.data, {'tuổi': '14p'});
    });

    test('dòng hỏng bị bỏ qua, không làm sập việc đọc', () async {
      await AppLog.i(LogSource.ui, LogTags.boot, 'mở app');
      await AppLog.flush();

      // Mô phỏng tiến trình bị giết giữa lúc append: một dòng JSON dở dang.
      final file = File('${tmp.path}/kato.log');
      await file.writeAsString('{"ts":123,"msg":"dở dan\n',
          mode: FileMode.writeOnlyAppend);
      await AppLog.i(LogSource.ui, LogTags.boot, 'sau dòng hỏng');
      await AppLog.flush();

      final entries = await AppLog.readAll();
      expect(entries.map((e) => e.message),
          containsAll(['mở app', 'sau dòng hỏng']));
      expect(entries.length, 2); // dòng hỏng không lọt vào
    });

    test('bỏ dòng cũ hơn hạn giữ (retention)', () async {
      final old = LogEntry(
        ts: DateTime.now()
            .subtract(const Duration(days: AppConfig.logRetentionDays + 1)),
        level: LogLevel.info,
        source: LogSource.alarm,
        tag: LogTags.cycle,
        message: 'quá hạn',
      );
      await File('${tmp.path}/kato.log')
          .writeAsString('${old.toJsonLine()}\n', mode: FileMode.writeOnlyAppend);
      await AppLog.i(LogSource.alarm, LogTags.cycle, 'còn hạn');
      await AppLog.flush();

      final entries = await AppLog.readAll();
      expect(entries.map((e) => e.message), ['còn hạn']);
    });

    test('rotate khi vượt trần kích thước, vẫn đọc được cả hai file', () async {
      // Ghi tới khi rotate thật sự xảy ra (không tự tính byte — kích thước dòng
      // JSON thay đổi thì phép tính tay sẽ lệch và test hoá ra không kiểm gì).
      final filler = 'x' * 2000;
      final rotated = File('${tmp.path}/kato.1.log');
      var i = 0;
      while (!rotated.existsSync() && i < 1000) {
        await AppLog.i(LogSource.fg, LogTags.cycle, '$filler $i');
        i++;
      }
      await AppLog.flush();

      expect(rotated.existsSync(), isTrue,
          reason: 'phải rotate sau ~${AppConfig.logMaxBytesPerFile} byte');
      expect(File('${tmp.path}/kato.log').existsSync(), isTrue);
      // Trần cứng: mỗi file không vượt quá ngưỡng quá nhiều.
      expect(File('${tmp.path}/kato.log').lengthSync(),
          lessThanOrEqualTo(AppConfig.logMaxBytesPerFile + 2200));

      final entries = await AppLog.readAll();
      expect(entries, isNotEmpty);
      // Đọc gộp cả file đã dồn: số dòng phải nhiều hơn số dòng của riêng file mới.
      final currentLines = File('${tmp.path}/kato.log').readAsLinesSync().length;
      expect(entries.length, greaterThan(currentLines));
    });

    test('cắt về logMaxEntries dòng gần nhất', () async {
      // Ghi trực tiếp vào file để không phải chờ 5000 lượt append.
      final sink = File('${tmp.path}/kato.log').openWrite(mode: FileMode.append);
      final now = DateTime.now();
      for (var i = 0; i < AppConfig.logMaxEntries + 50; i++) {
        sink.writeln(jsonEncode({
          'ts': now.subtract(Duration(seconds: i)).millisecondsSinceEpoch,
          'lvl': 0,
          'src': LogSource.alarm,
          'tag': LogTags.cycle,
          'msg': 'dòng $i',
        }));
      }
      await sink.flush();
      await sink.close();

      final entries = await AppLog.readAll();
      expect(entries.length, AppConfig.logMaxEntries);
      // Giữ các dòng MỚI nhất (i nhỏ = ts lớn).
      expect(entries.first.message, 'dòng 0');
    });

    test('clear xoá cả file đã dồn', () async {
      await AppLog.i(LogSource.ui, LogTags.boot, 'a');
      await AppLog.flush();
      await File('${tmp.path}/kato.1.log').writeAsString('{}\n');

      await AppLog.clear();
      expect(File('${tmp.path}/kato.log').existsSync(), isFalse);
      expect(File('${tmp.path}/kato.1.log').existsSync(), isFalse);
      expect(await AppLog.readAll(), isEmpty);
    });

    test('exportText xuất theo thứ tự cũ → mới, có tiêu đề ngày', () async {
      await AppLog.i(LogSource.alarm, LogTags.cycle, 'trước');
      await AppLog.i(LogSource.alarm, LogTags.notify, 'sau');
      await AppLog.flush();

      final text = await AppLog.exportText();
      expect(text, contains('nhật ký hoạt động'));
      expect(text.indexOf('trước'), lessThan(text.indexOf('sau')));
    });
  });

  group('LogEntry.tryParse', () {
    test('trả null với dòng rỗng / không phải JSON / thiếu ts', () {
      expect(LogEntry.tryParse(''), isNull);
      expect(LogEntry.tryParse('   '), isNull);
      expect(LogEntry.tryParse('không phải json'), isNull);
      expect(LogEntry.tryParse('{"msg":"thiếu ts"}'), isNull);
      expect(LogEntry.tryParse('[1,2,3]'), isNull);
    });

    test('lvl lạ rơi về info thay vì ném lỗi', () {
      final e = LogEntry.tryParse('{"ts":1000,"lvl":99,"msg":"x"}');
      expect(e, isNotNull);
      expect(e!.level, LogLevel.info);
    });
  });

  group('LogHealth', () {
    // Mốc gốc CỐ ĐỊNH: nếu mỗi entry tự gọi DateTime.now() thì các lượt gọi lệch
    // nhau vài micro giây, khiến khoảng cách 8h00 thành 7h59'59" và `inHours`
    // xuống 7 — test sẽ đo sai chứ không phải code sai.
    final base = DateTime(2026, 7, 27, 12);

    LogEntry entry(String tag, String src, Duration ago,
            {LogLevel level = LogLevel.info, Map<String, Object?>? data}) =>
        LogEntry(
          ts: base.subtract(ago),
          level: level,
          source: src,
          tag: tag,
          message: tag,
          data: data ?? const {},
        );

    test('suy ra mốc gần nhất và thống kê 24h', () {
      final entries = [
        entry(LogTags.notify, LogSource.alarm, const Duration(minutes: 5)),
        entry(LogTags.fetch, LogSource.alarm, const Duration(minutes: 6)),
        entry(LogTags.cycle, LogSource.alarm, const Duration(minutes: 6)),
        entry(LogTags.cycle, LogSource.fg, const Duration(minutes: 21)),
        entry(LogTags.db, LogSource.fg, const Duration(minutes: 30),
            level: LogLevel.error, data: {'err': 'database is locked'}),
        // Dòng ngoài cửa sổ 24h → không được tính vào thống kê.
        entry(LogTags.cycle, LogSource.fg, const Duration(hours: 30)),
      ];

      final h = LogHealth.from(entries, now: base);
      expect(h.cycles24h, 2); // 6 phút + 21 phút; dòng 30h nằm ngoài cửa sổ
      expect(h.fetches24h, 1);
      expect(h.notifies24h, 1);
      expect(h.errors24h, 1);
      expect(h.lastErrorMessage, 'database is locked');
      expect(h.lastCycleSource, LogSource.alarm);
    });

    test('nextAlarmAt chỉ lấy từ alarm chính, bỏ digest/announce', () {
      final soon = base.add(const Duration(minutes: 15));
      final entries = [
        entry(LogTags.arm, LogSource.digest, const Duration(minutes: 1),
            data: {
              'at': base.add(const Duration(hours: 9)).millisecondsSinceEpoch,
            }),
        entry(LogTags.arm, LogSource.alarm, const Duration(minutes: 2),
            data: {'at': soon.millisecondsSinceEpoch}),
      ];

      final h = LogHealth.from(entries, now: base);
      expect(h.nextAlarmAt?.millisecondsSinceEpoch, soon.millisecondsSinceEpoch);
    });

    test('longestGap24h phát hiện khoảng đứt dài (đêm mất chuỗi)', () {
      final entries = [
        // Chu kỳ sáng nay, rồi trước đó là tối qua → đứt 8 tiếng ở giữa.
        entry(LogTags.cycle, LogSource.alarm, const Duration(minutes: 10)),
        entry(LogTags.cycle, LogSource.alarm, const Duration(hours: 8, minutes: 10)),
        entry(LogTags.cycle, LogSource.alarm, const Duration(hours: 8, minutes: 25)),
      ];

      final h = LogHealth.from(entries, now: base);
      expect(h.longestGap24h!.inHours, 8);
    });

    test('nhật ký chưa trải hết 24h → KHÔNG báo động giả khoảng đứt', () {
      // Mới cài / vừa xoá nhật ký: chỉ có 2 chu kỳ trong 30 phút gần đây. Đoạn
      // 23 tiếng đầu cửa sổ chưa từng được quan sát nên không được tính là "ngủ".
      final entries = [
        entry(LogTags.cycle, LogSource.alarm, const Duration(minutes: 5)),
        entry(LogTags.cycle, LogSource.alarm, const Duration(minutes: 20)),
      ];

      final h = LogHealth.from(entries, now: base);
      expect(h.longestGap24h!.inMinutes, lessThan(20));
    });

    test('có chu kỳ trước cửa sổ → đoạn im lặng đầu cửa sổ được tính', () {
      final entries = [
        entry(LogTags.cycle, LogSource.alarm, const Duration(minutes: 5)),
        // Bằng chứng app đã chạy trước cửa sổ → 23h+ im lặng là thật.
        entry(LogTags.cycle, LogSource.alarm, const Duration(hours: 26)),
      ];

      final h = LogHealth.from(entries, now: base);
      expect(h.longestGap24h!.inHours, greaterThanOrEqualTo(23));
    });

    test('danh sách rỗng → mọi mốc null, không ném lỗi', () {
      final h = LogHealth.from(const []);
      expect(h.lastCycleAt, isNull);
      expect(h.longestGap24h, isNull);
      expect(h.cycles24h, 0);
    });
  });
}
