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

  try {
    // --- 1. last-known của hệ thống ---
    final pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      final age = DateTime.now().difference(pos.timestamp);
      if (age <=
          const Duration(hours: AppConfig.backgroundLastKnownMaxAgeHours)) {
        final coords =
            Coordinates(latitude: pos.latitude, longitude: pos.longitude);
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
      await AppLog.i(source, LogTags.loc, 'last-known quá cũ',
          data: {'tuổi': _fmtAge(age)});
    } else {
      await AppLog.i(source, LogTags.loc,
          'hệ thống không có last-known (cache vị trí rỗng)');
    }

    // --- 2. Toạ độ đang có đã cũ → XIN FIX MỚI ---
    final storedAge = stored?.age;
    final needFresh = stored == null ||
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

    // --- 3. Toạ độ đã lưu ---
    if (stored == null) {
      await AppLog.w(
        source,
        LogTags.loc,
        'KHÔNG có vị trí nào → bỏ chu kỳ (mở app một lần để lấy vị trí)',
      );
      return null;
    }
    final age = stored.age;
    final tooOld = age != null &&
        age > const Duration(hours: AppConfig.backgroundCoordsStaleWarnHours);
    await _logResolved(
      source,
      stored.coords,
      origin: 'toạ độ ĐÃ LƯU (không xin được fix mới)',
      age: age,
      previous: null,
      // Toạ độ quá cũ = thời tiết có thể KHÔNG phải nơi người dùng đang đứng.
      warn: tooOld,
      extraNote: tooOld
          ? 'toạ độ cũ hơn ${AppConfig.backgroundCoordsStaleWarnHours}h — thời '
              'tiết có thể KHÔNG đúng nơi bạn đang ở'
          : null,
    );
    return stored.coords;
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
      await AppLog.w(source, LogTags.loc,
          'dịch vụ vị trí đang TẮT → không xin được fix mới');
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
    'toạ độ': '${coords.latitude.toStringAsFixed(4)},'
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
    await AppLog.w(source, LogTags.loc, 'vị trí dùng cho chu kỳ này', data: data);
  } else {
    await AppLog.i(source, LogTags.loc, 'vị trí dùng cho chu kỳ này', data: data);
  }
}

String _fmtAge(Duration d) {
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes}p';
  if (d.inDays < 1) return '${d.inHours}h${d.inMinutes % 60}p';
  return '${d.inDays} ngày';
}
