import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/uv_advice.dart';

void main() {
  group('UvAdvice.classify', () {
    test('phân band theo thang WHO', () {
      expect(UvAdvice.classify(1).band, UvBand.low);
      expect(UvAdvice.classify(4).band, UvBand.moderate);
      expect(UvAdvice.classify(6).band, UvBand.high);
      expect(UvAdvice.classify(8).band, UvBand.veryHigh);
      expect(UvAdvice.classify(11).band, UvBand.extreme);
    });

    test('biên chuyển band đúng', () {
      expect(UvAdvice.classify(2.9).band, UvBand.low);
      expect(UvAdvice.classify(3).band, UvBand.moderate);
      expect(UvAdvice.classify(5.9).band, UvBand.moderate);
      expect(UvAdvice.classify(6).band, UvBand.high);
      expect(UvAdvice.classify(7.9).band, UvBand.high);
      expect(UvAdvice.classify(8).band, UvBand.veryHigh);
      expect(UvAdvice.classify(10.9).band, UvBand.veryHigh);
      expect(UvAdvice.classify(11).band, UvBand.extreme);
    });

    test('level làm tròn + luôn có lời khuyên', () {
      final uv = UvAdvice.classify(8.4);
      expect(uv.level, 8);
      expect(uv.label, 'Rất cao');
      expect(uv.advice, isNotEmpty);
    });

    test('needsProtection: từ trung bình trở lên', () {
      expect(UvAdvice.classify(1).needsProtection, false);
      expect(UvAdvice.classify(3).needsProtection, true);
      expect(UvAdvice.classify(9).needsProtection, true);
    });
  });
}
