import 'package:geolocator/geolocator.dart';

import '../../features/location/data/last_location_store.dart';
import '../../features/location/data/place_label_resolver.dart';
import '../../features/location/domain/entities/coordinates.dart';
import '../config/app_config.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';

/// Phân giải toạ độ dùng trong background isolate (chu kỳ nền, alarm, bản tin).
///
/// Thứ tự ưu tiên:
/// 1. `getLastKnownPosition` của hệ thống nếu còn tươi;
/// 2. **XIN FIX MỚI** (độ chính xác thấp, có timeout) nếu toạ độ đang có đã cũ —
///    đây là bước then chốt để nền BIẾT người dùng đã di chuyển;
/// 3. toạ độ đã lưu ([LastLocationStore]) làm lưới cuối.
///
/// ⚠️ Vì sao bước 2 tồn tại: trên máy thật `getLastKnownPosition()` rất hay trả
/// null (cache vị trí của hệ thống rỗng khi không app nào vừa định vị). Trước
/// đây nền rơi thẳng xuống bước 3, mà store đó CHỈ được cập nhật khi người dùng
/// mở app — nên đang di chuyển thì nền vẫn fetch thời tiết cho chỗ cũ và không
/// có dấu hiệu nào trong nhật ký. Nay mỗi lần phân giải đều ghi rõ: nguồn, tuổi,
/// tên địa điểm, và khoảng đã dịch chuyển so với lần trước.
///
/// [source] chỉ dùng cho nhật ký (biết lớp nào đang hỏi vị trí).
Future<Coordinates?> resolveBackgroundCoords({
  String source = LogSource.ui,
}) async {
  final store = LastLocationStore();
  StoredCoords? stored;
  try {
    stored = await store.readStored();
  } catch (_) {
    // Đọc store lỗi → coi như chưa có, các bước dưới vẫn chạy.
  }

  // last-known của hệ thống chưa đủ tươi để dùng ngay, nhưng vẫn còn dùng được
  // làm lưới cuối nếu không xin được fix mới (thà toạ độ cũ còn hơn bỏ chu kỳ).
  Coordinates? staleLastKnown;
  Duration? staleLastKnownAge;

  try {
    // --- 1. last-known của hệ thống ---
    final pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      final age = DateTime.now().difference(pos.timestamp);
      // ⚠️ CHỈ nhận ngay khi fix còn TƯƠI. Bản cũ nhận mọi fix tới 24 GIỜ tuổi
      // rồi `return` luôn, nên bước 2 ("toạ độ cũ hơn 25' thì xin fix mới" —
      // chính là bản sửa cho ca đi đường mà app báo thời tiết chỗ cũ) trở thành
      // CODE CHẾT: hệ thống hầu như luôn có sẵn một last-known nào đó. Tệ hơn,
      // `store.save()` bên dưới đóng dấu `savedAt = now` cho một toạ độ cũ hàng
      // giờ, nên lần sau bước 2 cũng tưởng toạ độ còn tươi.
      if (age <=
          const Duration(minutes: AppConfig.backgroundCoordsFreshMinutes)) {
        final coords = Coordinates(
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        await store.save(coords);
        await _logResolved(
          source,
          coords,
          origin: 'last-known hệ thống',
          age: age,
          previous: stored?.coords,
        );
        return coords;
      }
      // Chưa đủ tươi → thử xin fix mới ở bước 2; nếu không xin được thì bước 3
      // vẫn còn dùng lại được nó (miễn chưa quá `backgroundLastKnownMaxAgeHours`).
      await AppLog.i(
        source,
        LogTags.loc,
        'last-known chưa đủ tươi → sẽ thử xin fix mới',
        data: {
          'tuổi': _fmtAge(age),
          'ngưỡng': '${AppConfig.backgroundCoordsFreshMinutes}p',
        },
      );
      if (age <=
          const Duration(hours: AppConfig.backgroundLastKnownMaxAgeHours)) {
        staleLastKnown = Coordinates(
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        staleLastKnownAge = age;
      }
    } else {
      await AppLog.i(
        source,
        LogTags.loc,
        'hệ thống không có last-known (cache vị trí rỗng)',
      );
    }

    // --- 2. Toạ độ đang có đã cũ → XIN FIX MỚI ---
    final storedAge = stored?.age;
    final needFresh =
        stored == null ||
        storedAge == null ||
        storedAge >
            const Duration(minutes: AppConfig.backgroundCoordsFreshMinutes);
    if (needFresh) {
      final fresh = await _requestFreshFix(source);
      if (fresh != null) {
        await store.save(fresh);
        await _logResolved(
          source,
          fresh,
          origin: 'fix MỚI vừa xin',
          age: Duration.zero,
          previous: stored?.coords,
        );
        return fresh;
      }
    }

    // --- 3. Lưới cuối: toạ độ đã lưu, hoặc last-known cũ ở bước 1 ---
    //
    // Chọn cái MỚI HƠN trong hai nguồn. Không có mốc tuổi thì coi như cũ nhất:
    // thà dùng nguồn biết chắc tuổi còn hơn nguồn mù mờ.
    var fallback = stored?.coords;
    var age = stored?.age;
    var origin = 'toạ độ ĐÃ LƯU (không xin được fix mới)';
    if (staleLastKnown != null &&
        (fallback == null || age == null || staleLastKnownAge! < age)) {
      fallback = staleLastKnown;
      age = staleLastKnownAge;
      origin = 'last-known hệ thống CŨ (không xin được fix mới)';
    }

    if (fallback == null) {
      await AppLog.w(
        source,
        LogTags.loc,
        'KHÔNG có vị trí nào → bỏ chu kỳ (mở app một lần để lấy vị trí)',
      );
      return null;
    }
    final tooOld =
        age != null &&
        age > const Duration(hours: AppConfig.backgroundCoordsStaleWarnHours);
    await _logResolved(
      source,
      fallback,
      origin: origin,
      age: age,
      previous: null,
      // Toạ độ quá cũ = thời tiết có thể KHÔNG phải nơi người dùng đang đứng.
      warn: tooOld,
      extraNote: tooOld
          ? 'toạ độ cũ hơn ${AppConfig.backgroundCoordsStaleWarnHours}h — thời '
                'tiết có thể KHÔNG đúng nơi bạn đang ở'
          : null,
    );
    return fallback;
  } catch (e, st) {
    await AppLog.e(
      source,
      LogTags.loc,
      'lỗi khi phân giải vị trí nền',
      error: e,
      stack: st,
    );
    return stored?.coords;
  }
}

/// Xin một fix vị trí MỚI ở nền: độ chính xác thấp (đủ cho thời tiết, tiết kiệm
/// pin) + timeout ngắn để không treo chu kỳ nền.
///
/// Trả null khi: thiếu quyền vị trí nền, service tắt, hoặc hết thời gian chờ —
/// mọi trường hợp đều ghi log để đọc nhật ký là biết lý do.
Future<Coordinates?> _requestFreshFix(String source) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await AppLog.w(
        source,
        LogTags.loc,
        'dịch vụ vị trí đang TẮT → không xin được fix mới',
      );
      return null;
    }
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      // `whileInUse` KHÔNG đủ cho isolate nền → đây là lý do rất hay gặp khiến
      // nền mãi dùng toạ độ cũ. Nói rõ trong nhật ký để người dùng biết cách sửa.
      await AppLog.w(
        source,
        LogTags.loc,
        'quyền vị trí là "${permission.name}" — cần "Luôn cho phép" để nền tự '
        'cập nhật vị trí khi bạn di chuyển',
      );
      if (permission != LocationPermission.whileInUse) return null;
      // Vẫn thử: một số máy cho phép khi foreground service đang chạy.
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: AppConfig.backgroundFixTimeoutSeconds),
      ),
    );
    return Coordinates(latitude: pos.latitude, longitude: pos.longitude);
  } catch (e) {
    await AppLog.w(
      source,
      LogTags.loc,
      'xin fix vị trí mới KHÔNG thành công → dùng toạ độ đã lưu',
      data: {'err': e.toString()},
    );
    return null;
  }
}

/// Ghi một dòng nhật ký ĐẦY ĐỦ về vị trí đang dùng: nguồn, toạ độ, tuổi, khoá
/// cache, **ĐỊA CHỈ THỰC TẾ** (số nhà → đường → phường/xã → quận/huyện →
/// tỉnh/thành), và khoảng đã dịch chuyển so với [previous].
///
/// Địa chỉ do [PlaceLabelResolver] dựng (Nominatim + cache + fallback plugin) —
/// trước đây chỗ này chỉ có nhãn thô tới cấp tỉnh/thành, nên đọc nhật ký không
/// kiểm chứng được app có lấy thời tiết đúng nơi mình đứng hay không.
Future<void> _logResolved(
  String source,
  Coordinates coords, {
  required String origin,
  Duration? age,
  Coordinates? previous,
  bool warn = false,
  String? extraNote,
}) async {
  final data = <String, Object?>{
    'nguồn': origin,
    'toạ độ':
        '${coords.latitude.toStringAsFixed(4)},'
        '${coords.longitude.toStringAsFixed(4)}',
    'tuổi': age == null ? 'chưa rõ' : _fmtAge(age),
    'khoá cache': coords.cacheKey,
  };

  final address = await PlaceLabelResolver.describe(coords);
  data['địa chỉ'] = address ?? 'chưa tra được (mạng lỗi?)';

  if (previous != null) {
    final moved = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      coords.latitude,
      coords.longitude,
    );
    data['đã dịch chuyển'] = moved >= 1000
        ? '${(moved / 1000).toStringAsFixed(1)}km'
        : '${moved.round()}m';
    if (moved >= AppConfig.locationMovedNoticeMeters) {
      data['ghi chú'] = 'ĐỔI KHU VỰC so với lần trước';
    }
  }
  if (extraNote != null) data['cảnh báo'] = extraNote;

  if (warn) {
    await AppLog.w(
      source,
      LogTags.loc,
      'vị trí dùng cho chu kỳ này',
      data: data,
    );
  } else {
    await AppLog.i(
      source,
      LogTags.loc,
      'vị trí dùng cho chu kỳ này',
      data: data,
    );
  }
}

String _fmtAge(Duration d) {
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes}p';
  if (d.inDays < 1) return '${d.inHours}h${d.inMinutes % 60}p';
  return '${d.inDays} ngày';
}
