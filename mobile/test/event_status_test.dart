import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/announcements/domain/entities/exam_event.dart';
import 'package:katocast/features/announcements/domain/entities/event_status.dart';

void main() {
  ExamEvent jlptJuly() => ExamEvent(
        topic: 'jlpt',
        sessionLabel: 'JLPT Kỳ 7/2026',
        regStart: DateTime(2026, 3, 17),
        regEnd: DateTime(2026, 4, 7),
        examDate: DateTime(2026, 7, 5),
        curated: true,
      );

  test('sau kỳ thi & hết hạn đăng ký → "Đã hết hạn đăng ký · Đã thi"', () {
    final s = computeStatus(jlptJuly(), DateTime(2026, 7, 10));
    expect(s.summaryLabel, contains('Đã hết hạn đăng ký'));
    expect(s.summaryLabel, contains('Đã thi'));
  });

  test('đang mở đăng ký → good/warning + còn N ngày', () {
    final s = computeStatus(jlptJuly(), DateTime(2026, 3, 20));
    expect(s.summaryLabel, contains('Đang mở đăng ký'));
    expect(s.level, anyOf(StatusLevel.good, StatusLevel.warning));
  });

  test('trước khi mở đăng ký → neutral', () {
    final s = computeStatus(jlptJuly(), DateTime(2026, 1, 1));
    expect(s.summaryLabel, contains('Đăng ký mở sau'));
    expect(s.level, StatusLevel.neutral);
  });

  test('sắp thi (đăng ký đã đóng) → còn N ngày đến ngày thi', () {
    final s = computeStatus(jlptJuly(), DateTime(2026, 7, 1));
    expect(s.summaryLabel, contains('Còn 4 ngày đến ngày thi'));
  });

  test('không có mốc nào → thông báo mặc định', () {
    final s = computeStatus(
        const ExamEvent(topic: 'custom', sessionLabel: 'X'), DateTime(2026, 7, 10));
    expect(s.summaryLabel, 'Chưa có mốc thời gian');
  });
}
