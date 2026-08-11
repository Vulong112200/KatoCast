import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/weather/domain/entities/hourly.dart';
import 'package:katocast/features/weather/domain/entities/minutely.dart';
import 'package:katocast/features/weather/presentation/widgets/hourly_list.dart';

/// `effectiveHourPop` — con số % hiện trên `HourlyList`.
///
/// Quy tắc: lấy giá trị LỚN HƠN giữa nowcast 15' (max các mốc trong khối giờ) và
/// `hourly.pop`. App không bao giờ được hiện khả năng mưa THẤP HƠN con số OWM đưa
/// ra ở bất kỳ nguồn nào — báo hụt chính là chiều đã gây ra vụ 10/08/2026.
void main() {
  final t = DateTime(2026, 8, 11, 18);

  HourlyForecast hour(double pop) => HourlyForecast(
        time: t,
        tempC: 30,
        humidity: 80,
        pop: pop,
        rainMm: 0,
        description: '',
        icon: '',
      );

  MinutelyForecast slot(int minute, double pop) => MinutelyForecast(
        time: t.add(Duration(minutes: minute)),
        precipitationMmH: 0,
        pop: pop,
      );

  test('ca thật 11/08: hourly 0% nhưng nowcast 17% ⇒ hiện 17%', () {
    // Đo thật ở TP.HCM: giờ 18:00 hourly báo pop=0 trong khi các mốc nowcast
    // trong cùng giờ đó báo tới 0.17. Nowcast nhạy hơn với mưa sắp tới.
    final pop = effectiveHourPop(
      hour(0),
      [slot(0, 0.0), slot(15, 0.05), slot(30, 0.17), slot(45, 0.12)],
    );
    expect(pop, closeTo(0.17, 1e-9));
  });

  test('nowcast THẤP hơn hourly ⇒ vẫn hiện số của hourly (không báo hụt)', () {
    // Đây là điều bản trước làm SAI: nowcast có dữ liệu là thay thế hẳn hourly,
    // nên trường hợp này app sẽ hiện 5% dù OWM dự báo 40%.
    final pop = effectiveHourPop(
      hour(0.40),
      [slot(0, 0.05), slot(15, 0.03), slot(30, 0.05), slot(45, 0.02)],
    );
    expect(pop, closeTo(0.40, 1e-9));
  });

  test('không có mốc nowcast nào trong giờ ⇒ dùng hourly.pop', () {
    // Giờ xa, ngoài tầm nowcast (~12h).
    expect(effectiveHourPop(hour(0.35), const []), closeTo(0.35, 1e-9));
    final pop = effectiveHourPop(
      hour(0.35),
      [
        MinutelyForecast(
          time: t.add(const Duration(hours: 3)),
          precipitationMmH: 0,
          pop: 0.9,
        ),
      ],
    );
    expect(pop, closeTo(0.35, 1e-9));
  });

  test('chỉ lấy mốc TRONG khối giờ [t, t+1h)', () {
    // Mốc đúng đầu giờ sau KHÔNG được tính vào giờ này.
    final pop = effectiveHourPop(
      hour(0.10),
      [slot(59, 0.20), slot(60, 0.95)],
    );
    expect(pop, closeTo(0.20, 1e-9));
  });
}
