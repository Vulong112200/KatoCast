import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/features/location/data/place_label_resolver.dart';
import 'package:katocast/features/location/domain/entities/coordinates.dart';
import 'package:katocast/features/location/domain/entities/place.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toạ độ gốc (khu vực TP.HCM, giống nhật ký thật).
const _base = Coordinates(latitude: 10.8524, longitude: 106.6507);

Place _place(Coordinates c) => Place(
      coordinates: c,
      thoroughfare: '12 Đường Nguyễn Văn Bảo',
      subLocality: 'Phường 4',
      subAdministrativeArea: 'Quận Gò Vấp',
      administrativeArea: 'Thành phố Hồ Chí Minh',
      country: 'Việt Nam',
    );

/// Dịch [c] đi [meters] về phía bắc (≈ 1 độ vĩ = 111.32 km).
Coordinates _movedNorth(Coordinates c, double meters) => Coordinates(
      latitude: c.latitude + meters / 111320.0,
      longitude: c.longitude,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlaceLabelResolver.debugReset();
  });

  test('nhãn cache là ĐỊA CHỈ ĐẦY ĐỦ: số nhà → đường → phường → quận → thành phố',
      () async {
    // Đây chính là điều nhật ký còn thiếu: trước đây chỉ có "Thành phố Hồ Chí
    // Minh, Hồ Chí Minh" nên nhìn toạ độ không kiểm chứng được đúng/sai.
    await PlaceLabelResolver.seedCache(_base, _place(_base));

    final label = await PlaceLabelResolver.describe(_base);
    expect(label, '12 Đường Nguyễn Văn Bảo, Phường 4, Quận Gò Vấp, '
        'Thành phố Hồ Chí Minh');
  });

  test('nhiễu GPS trong bán kính cho phép ⇒ DÙNG LẠI cache (không gọi mạng)',
      () async {
    await PlaceLabelResolver.seedCache(_base, _place(_base));
    // Nhật ký thật cho thấy toạ độ rung 0–51m dù máy đứng yên. Nếu cache so
    // theo khoá làm tròn thì một bước nhiễu qua biên là mất cache → mỗi chu kỳ
    // nền lại bắn một request Nominatim (vi phạm chính sách OSM ~1 req/s).
    final jittered = _movedNorth(_base, 50);
    expect(await PlaceLabelResolver.describe(jittered), isNotNull);
  });

  test('đi xa quá bán kính ⇒ KHÔNG dùng cache (địa chỉ đã khác)', () async {
    await PlaceLabelResolver.seedCache(_base, _place(_base));
    final farAway =
        _movedNorth(_base, PlaceLabelResolver.reuseRadiusMeters + 200);

    // Không có mạng trong môi trường test → describe trả null, nhưng điều cần
    // khẳng định là nó KHÔNG trả nhãn của chỗ cũ (báo sai vị trí còn tệ hơn
    // không báo gì).
    final label = await PlaceLabelResolver.describe(farAway);
    expect(label, isNot('12 Đường Nguyễn Văn Bảo, Phường 4, Quận Gò Vấp, '
        'Thành phố Hồ Chí Minh'));
  });

  test('cache quá cũ ⇒ không dùng lại', () async {
    await PlaceLabelResolver.seedCache(_base, _place(_base));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'place_label_at_ms',
      DateTime.now()
          .subtract(PlaceLabelResolver.maxAge + const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    expect(await PlaceLabelResolver.describe(_base), isNot(contains('Gò Vấp')));
  });

  test('Place không có tên nào ⇒ KHÔNG cache toạ độ làm "địa chỉ"', () async {
    // `Place.fullLabel` fallback về toạ độ khi thiếu tên. In toạ độ ở cột "địa
    // chỉ" ngay cạnh cột "toạ độ" là vô nghĩa, nên phải bị loại.
    await PlaceLabelResolver.seedCache(
      _base,
      const Place(coordinates: _base),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('place_label_text'), isNull);
  });

  test('hàng rào giãn cách: hai lượt liền nhau chỉ cho gọi mạng MỘT lần',
      () async {
    // Không có cache và không có mạng → cả hai lượt trả null; điều cần khẳng
    // định là mốc gọi đã được ghi ngay lượt đầu để lượt sau bị chặn (tôn trọng
    // chính sách OSM khi 3 lớp trigger cùng chạy mỗi 5–15').
    await PlaceLabelResolver.describe(_base);
    final prefs = await SharedPreferences.getInstance();
    final firstCallMs = prefs.getInt('place_label_last_call_ms');
    expect(firstCallMs, isNotNull);

    await PlaceLabelResolver.describe(_base);
    expect(prefs.getInt('place_label_last_call_ms'), firstCallMs,
        reason: 'lượt thứ hai phải bị hàng rào giãn cách chặn');
  });
}
