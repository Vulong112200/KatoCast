import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/weather_condition.dart';

void main() {
  group('WeatherCondition.classify - mã điều kiện OpenWeatherMap', () {
    test('800 ⇒ trời nắng (info)', () {
      final c = WeatherCondition.classify(800);
      expect(c.category, WeatherCategory.clear);
      expect(c.severity, WeatherSeverity.info);
    });

    test('803 ⇒ nhiều mây', () {
      expect(WeatherCondition.classify(803).category, WeatherCategory.cloudy);
    });

    test('500 ⇒ mưa nhỏ; 501 ⇒ mưa vừa; 502 ⇒ mưa to (warning)', () {
      expect(WeatherCondition.classify(500).category, WeatherCategory.lightRain);
      expect(
          WeatherCondition.classify(501).category, WeatherCategory.moderateRain);
      final heavy = WeatherCondition.classify(502);
      expect(heavy.category, WeatherCategory.heavyRain);
      expect(heavy.severity, WeatherSeverity.warning);
    });

    test('503/504 ⇒ mưa rất to (severe)', () {
      expect(WeatherCondition.classify(503).severity, WeatherSeverity.severe);
    });

    test('lượng mưa lớn nâng cấp 500 thành mưa to', () {
      final c = WeatherCondition.classify(500, rainMmH: 3.0);
      expect(c.category, WeatherCategory.heavyRain);
    });

    test('2xx ⇒ dông; 212/221 ⇒ bão lớn (severe)', () {
      expect(
          WeatherCondition.classify(201).category, WeatherCategory.thunderstorm);
      expect(WeatherCondition.classify(212).category, WeatherCategory.severeStorm);
    });

    test('781 ⇒ lốc xoáy (severe)', () {
      final c = WeatherCondition.classify(781);
      expect(c.category, WeatherCategory.severeStorm);
      expect(c.severity, WeatherSeverity.severe);
    });
  });
}
