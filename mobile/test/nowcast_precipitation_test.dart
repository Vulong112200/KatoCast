import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/config/app_config.dart';
import 'package:katocast/features/weather/data/datasources/weather_remote_datasource.dart';

/// Chốt lại LỖI GỐC của vụ 10/08/2026: nowcast 15' luôn bằng 0.
///
/// Endpoint `/onecall/timeline/15min` của One Call **4.0 KHÔNG BAO GIỜ** trả
/// trường `rain` — xác minh bằng API thật ngày 11/08/2026:
/// - Manila: `current` id=502 kèm `rain.1h` = 6.1 mm (mưa to thật), nhưng
///   **0/50** bản ghi 15' có `rain`; mỗi bản ghi chỉ có `pop` + `weather[].id`.
/// - Mumbai (id=501): y hệt, 0/50.
/// - Ngược lại `/timeline/1h` CÓ `rain` đầy đủ (20/20) — nên hourly vẫn đúng.
///
/// Bản cũ đọc `rain` từ bản ghi 15' nên chuỗi nowcast bị ghim cứng 0.0. Nhật ký
/// thật ghi `nowcast bây giờ = 0.00 mm/h` ở **168/168** chu kỳ suốt 2 ngày, kể
/// cả 37 chu kỳ mà `current` đang báo mã 500 kèm lượng mưa đo được.
void main() {
  double precip(Object? weather) =>
      WeatherRemoteDataSource.precipFromCondition(weather);

  /// Bản ghi 15' NGUYÊN VĂN từ Manila lúc đang mưa to — chú ý: KHÔNG có `rain`.
  const manila15minRecord = {
    'dt': 1786413600,
    'temp': 28.37,
    'humidity': 86,
    'clouds': 26,
    'pop': 1,
    'weather': [
      {
        'id': 501,
        'main': 'Rain',
        'description': 'moderate rain',
        'icon': '10d',
      },
    ],
  };

  group('nowcast 15p suy lượng mưa từ weather[].id (KHÔNG có trường rain)', () {
    test(
      'ca thật Manila: bản ghi mưa vừa, không rain ⇒ VẪN ra lượng mưa > 0',
      () {
        // Đây chính là dòng đã hỏng: bản cũ đọc record['rain'] → null → 0.0.
        expect(
          manila15minRecord.containsKey('rain'),
          isFalse,
          reason: 'payload thật của 4.0 không có trường rain ở timeline 15min',
        );
        final mmH = precip(manila15minRecord['weather']);
        expect(mmH, greaterThan(0));
        expect(mmH, greaterThanOrEqualTo(AppConfig.rainNowThresholdMmH));
      },
    );

    test('mã 500 (mưa nhỏ) ⇒ vượt ngưỡng ĐANG mưa', () {
      // Ca 10/08 18:03 của người dùng: OWM current báo mã 500. Nếu nowcast cũng
      // ở mã 500 mà app vẫn ra 0.0 thì không đường nào phát hiện được mưa.
      final mmH = precip([
        {'id': 500},
      ]);
      expect(mmH, greaterThanOrEqualTo(AppConfig.rainNowThresholdMmH));
    });

    test('thang cường độ tăng dần theo mã: 500 < 501 < 502', () {
      final light = precip([
        {'id': 500},
      ]);
      final moderate = precip([
        {'id': 501},
      ]);
      final heavy = precip([
        {'id': 502},
      ]);
      expect(light, lessThan(moderate));
      expect(moderate, lessThan(heavy));
    });

    test('dông 2xx ⇒ mức mưa to (bỏ sót dông nguy hiểm hơn báo dư)', () {
      expect(
        precip([
          {'id': 202},
        ]),
        greaterThanOrEqualTo(AppConfig.rainNowObviousMmH),
      );
    });

    test('trời quang/mây/sương mù ⇒ 0.0 (không được bịa ra mưa)', () {
      for (final id in [800, 801, 804, 701, 741]) {
        expect(
          precip([
            {'id': id},
          ]),
          0.0,
          reason: 'mã $id không phải mưa',
        );
      }
    });

    test('KHÔNG mức nào rơi vào vùng chết 0.1–0.49 mm/h', () {
      // Vùng chết: quá yếu để tuyên bố "đang mưa", nhưng đủ để mốc kế tiếp bị
      // gán "sắp mưa" ⇒ pha kẹt `rainStartingSoon` và app im lặng vĩnh viễn.
      // Bảng ánh xạ cố ý tránh dải này: mỗi mã hoặc 0.0, hoặc ≥ 0.5.
      const allCodes = [
        200, 201, 202, 210, 211, 212, 221, 230, 231, 232, //
        300, 301, 302, 310, 311, 312, 313, 314, 321, //
        500, 501, 502, 503, 504, 511, 520, 521, 522, 531, //
        600, 601, 602, 611, 612, 615, 616, 620, 621, 622, //
        701, 711, 721, 731, 741, 751, 761, 771, 781, //
        800, 801, 802, 803, 804,
      ];
      for (final id in allCodes) {
        final mmH = precip([
          {'id': id},
        ]);
        final inDeadZone =
            mmH > AppConfig.rainThresholdMmH &&
            mmH < AppConfig.rainNowThresholdMmH;
        expect(
          inDeadZone,
          isFalse,
          reason: 'mã $id cho $mmH mm/h — rơi vào vùng chết',
        );
      }
    });

    test('payload méo (thiếu weather / sai kiểu) ⇒ 0.0, không ném lỗi', () {
      expect(precip(null), 0.0);
      expect(precip(const []), 0.0);
      expect(precip('không phải list'), 0.0);
      expect(
        precip([
          {'không có id': 1},
        ]),
        0.0,
      );
    });
  });
}
