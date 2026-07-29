import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/background/alarm_schedule_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('claimSchedule (throttle self-heal)', () {
    test('lần đầu luôn cho qua', () async {
      expect(await AlarmScheduleGuard.claimSchedule('k'), isTrue);
    });

    test('lần thứ hai ngay sau đó bị chặn', () async {
      expect(await AlarmScheduleGuard.claimSchedule('k'), isTrue);
      // Đây là ca thật: mỗi chu kỳ nền đều gọi lập lịch; nếu không chặn thì lệnh
      // cancel + đặt lại sẽ đua với re-arm từ isolate alarm.
      expect(await AlarmScheduleGuard.claimSchedule('k'), isFalse);
    });

    test('force bỏ qua throttle (người dùng đổi cài đặt)', () async {
      expect(await AlarmScheduleGuard.claimSchedule('k'), isTrue);
      expect(await AlarmScheduleGuard.claimSchedule('k', force: true), isTrue);
    });

    test('hết khoảng throttle thì cho qua lại', () async {
      expect(await AlarmScheduleGuard.claimSchedule('k'), isTrue);
      expect(
        await AlarmScheduleGuard.claimSchedule(
          'k',
          throttle: Duration.zero,
        ),
        isTrue,
      );
    });

    test('các khoá khác nhau không chặn nhau (bản tin vs poll tin)', () async {
      expect(await AlarmScheduleGuard.claimSchedule('digest'), isTrue);
      expect(await AlarmScheduleGuard.claimSchedule('announce'), isTrue);
    });
  });

  group('justPassed', () {
    final now = DateTime(2026, 7, 27, 6, 40); // 6:40

    test('mốc vừa trôi qua trong grace → true', () {
      // 6:30 đã qua 10 phút → alarm của nó đang chờ/đã nổ, đừng đụng vào.
      expect(AlarmScheduleGuard.justPassed(now, 6 * 60 + 30), isTrue);
    });

    test('mốc trôi qua lâu hơn grace → false', () {
      expect(AlarmScheduleGuard.justPassed(now, 6 * 60), isFalse);
    });

    test('mốc còn ở tương lai → false', () {
      expect(AlarmScheduleGuard.justPassed(now, 16 * 60 + 30), isFalse);
    });

    test('đúng mốc (0 phút) → true', () {
      expect(AlarmScheduleGuard.justPassed(now, 6 * 60 + 40), isTrue);
    });

    test('biên grace: đúng 20 phút → true, 21 phút → false', () {
      expect(AlarmScheduleGuard.justPassed(now, 6 * 60 + 20), isTrue);
      expect(AlarmScheduleGuard.justPassed(now, 6 * 60 + 19), isFalse);
    });
  });

  group('nextInstanceOf', () {
    test('mốc chưa qua hôm nay → hôm nay', () {
      final from = DateTime(2026, 7, 27, 5);
      final next = AlarmScheduleGuard.nextInstanceOf(6 * 60 + 30, from: from);
      expect(next, DateTime(2026, 7, 27, 6, 30));
    });

    test('mốc đã qua → ngày mai', () {
      final from = DateTime(2026, 7, 27, 7);
      final next = AlarmScheduleGuard.nextInstanceOf(6 * 60 + 30, from: from);
      expect(next, DateTime(2026, 7, 28, 6, 30));
    });

    test('đúng mốc hiện tại → ngày mai (không đặt vào quá khứ/ngay lập tức)', () {
      final from = DateTime(2026, 7, 27, 6, 30);
      final next = AlarmScheduleGuard.nextInstanceOf(6 * 60 + 30, from: from);
      expect(next, DateTime(2026, 7, 28, 6, 30));
    });

    test('qua ranh giới cuối tháng', () {
      final from = DateTime(2026, 7, 31, 23, 50);
      final next = AlarmScheduleGuard.nextInstanceOf(6 * 60 + 30, from: from);
      expect(next, DateTime(2026, 8, 1, 6, 30));
    });
  });
}
