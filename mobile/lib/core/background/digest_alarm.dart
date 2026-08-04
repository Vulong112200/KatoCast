import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_daily_digest.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import 'background_location.dart';
import 'cycle_lock.dart';

/// Entry-point do AndroidAlarmManager gọi ĐÚNG mốc giờ bản tin (kể cả khi app đã
/// tắt / màn hình tắt). Chạy trong isolate riêng → tự dựng dependency, KHÔNG dùng
/// Riverpod. [id] = `NotificationIds.digestBase + index`, với `index` là vị trí
/// mốc trong danh sách [DigestPrefs.times] (đã sort).
///
/// Khác cơ chế cũ (`zonedSchedule` bake sẵn text lúc lập lịch → hiển thị dữ liệu
/// cũ): callback này FETCH DỮ LIỆU TƯƠI ngay tại thời điểm bắn rồi mới hiển thị.
///
/// Vì lịch dùng `oneShotAt` (không tự lặp — cần thiết để nổ đúng giờ trong Doze),
/// callback PHẢI tự đặt lại mốc cho ngày mai ở cuối (kể cả khi bỏ hiển thị vì
/// thiếu vị trí/offline), trừ khi bản tin đã tắt hoặc mốc đã bị xóa.
@pragma('vm:entry-point')
void digestAlarmCallback(int id) {
  if (id == NotificationIds.digestTest) {
    _runDigestTest();
    return;
  }
  _runDigest(id);
}

/// Bản tin THỬ: chỉ hiển thị một thông báo xác nhận (KHÔNG fetch thời tiết, KHÔNG
/// re-arm, KHÔNG phụ thuộc bản tin bật/tắt) → cô lập đúng khâu giao alarm nền để
/// người dùng tự chẩn đoán force-stop.
Future<void> _runDigestTest() async {
  const src = LogSource.digest;
  try {
    await AppLog.i(src, LogTags.digest, 'BẢN TIN THỬ nổ đúng giờ');
    final notif = NotificationService();
    await notif.init();
    await notif.show(
      id: NotificationIds.digestTest,
      title: '✅ Thông báo nền hoạt động',
      body: 'Bản tin thử đã nổ đúng giờ. Nếu bạn VUỐT TẮT app mà thông báo này '
          'KHÔNG xuất hiện, hãy bật "Tự khởi động" + đặt pin "Không giới hạn".',
    );
  } catch (e, st) {
    await AppLog.e(src, LogTags.digest, 'lỗi hiển thị bản tin thử',
        error: e, stack: st);
  } finally {
    await AppLog.flush();
  }
}

Future<void> _runDigest(int id) async {
  const src = LogSource.digest;
  await AppLog.i(src, LogTags.cycle, 'alarm bản tin nổ', data: {'id': id});

  final prefs = await _readPrefsSafely(src);

  // RE-ARM TRƯỚC, LÀM VIỆC SAU.
  //
  // Trước đây re-arm nằm ở `finally` cuối hàm. Nhưng isolate nền có thể bị OEM
  // giết BẤT KỲ LÚC NÀO giữa chu kỳ (đã quan sát: alarm nổ 06:34:03 rồi tiến
  // trình chết, không kịp re-arm → chuỗi đứt 7h18). Đặt lại lịch ngay từ đầu
  // biến chuỗi thành tự duy trì: dù phần dưới có chết thì mốc ngày mai đã nằm
  // trong AlarmManager của hệ thống.
  await _rearmTomorrow(id, prefs, src);

  if (prefs == null || !prefs.enabled) {
    await AppLog.i(src, LogTags.digest, 'bản tin đang TẮT → bỏ mốc này');
    return;
  }

  try {
    final coords = await resolveBackgroundCoords(source: src);
    if (coords == null) return; // đã re-arm ở trên.

    // Bản tin CHỜ lock chứ KHÔNG bỏ lượt: đây là thông báo mỗi ngày một lần mà
    // người dùng đang đợi. Bug thật đã quan sát: bản tin nổ đúng lúc WorkManager
    // giữ lock → bị bỏ lượt → mất hẳn bản tin của ngày đó.
    await CycleLock.runWaiting(src, () async {
      final db = AppDatabase();
      final api = ApiClient.create();
      try {
        final repo = WeatherRepositoryImpl(
          WeatherRemoteDataSource(api),
          WeatherLocalDataSource(db),
          NetworkInfoImpl(Connectivity()),
          logSource: src,
        );
        // forceRefresh: cố lấy tươi; offline sẽ fallback cache trong repo.
        final result = await repo.getWeather(coords, forceRefresh: true);
        final data = result.fold((_) => null, (d) => d);
        if (data == null) {
          await AppLog.w(src, LogTags.digest,
              'không có dữ liệu (offline & chưa có cache) → bỏ mốc này');
          return;
        }

        final digest = const BuildDailyDigest().call(data);
        final notif = NotificationService();
        await notif.init();
        await notif.show(id: id, title: digest.title, body: digest.body);
        await AppLog.i(
          src,
          LogTags.notify,
          'ĐÃ GỬI BẢN TIN: ${digest.title}',
          data: {'id': id, 'nội dung': digest.body},
        );
      } finally {
        api.close();
        try {
          await db.close();
        } catch (e, st) {
          await AppLog.e(src, LogTags.db, 'lỗi đóng DB', error: e, stack: st);
        }
      }
    });
  } catch (e, st) {
    await AppLog.e(src, LogTags.digest, 'lỗi khi dựng bản tin',
        error: e, stack: st);
  } finally {
    await AppLog.flush();
  }
}

/// Đọc cài đặt bản tin, trả null nếu lỗi (để vẫn re-arm được theo đường dự phòng).
Future<DigestPrefs?> _readPrefsSafely(String src) async {
  try {
    return await NotificationPrefsStore().read();
  } catch (e, st) {
    await AppLog.e(src, LogTags.digest, 'không đọc được cài đặt bản tin',
        error: e, stack: st);
    return null;
  }
}

/// Đặt lại alarm cho NGÀY MAI (one-shot không tự lặp). Chỉ khi bản tin còn bật
/// VÀ mốc (index) này vẫn tồn tại trong danh sách.
Future<void> _rearmTomorrow(int id, DigestPrefs? prefs, String src) async {
  try {
    final index = id - NotificationIds.digestBase;
    if (prefs == null) {
      // Không đọc được cài đặt → vẫn giữ chuỗi sống bằng mốc mặc định thay vì
      // để nó đứt hẳn (thà bản tin lệch giờ còn hơn im lặng mãi).
      await scheduleDigestSlot(id, AppConfig.digestDefaultMorningMinutes,
          source: src);
      await AppLog.w(src, LogTags.arm,
          're-arm bằng mốc mặc định vì không đọc được cài đặt', data: {'id': id});
      return;
    }
    if (prefs.enabled && index >= 0 && index < prefs.times.length) {
      await scheduleDigestSlot(id, prefs.times[index], source: src);
    } else {
      await AppLog.i(
        src,
        LogTags.digest,
        'KHÔNG re-arm mốc này',
        data: {
          'id': id,
          'lý do':
              prefs.enabled ? 'mốc đã bị xoá khỏi cài đặt' : 'bản tin đã tắt',
        },
      );
    }
  } catch (e, st) {
    await AppLog.e(
      src,
      LogTags.arm,
      'RE-ARM bản tin THẤT BẠI — mốc này có thể mất tới khi mở lại app',
      error: e,
      stack: st,
      data: {'id': id},
    );
  }
}
