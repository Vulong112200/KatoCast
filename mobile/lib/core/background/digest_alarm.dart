import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_daily_digest.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
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

  DigestPrefs? prefs;
  try {
    // Tôn trọng cài đặt: người dùng đã tắt bản tin thì không hiển thị (và không
    // re-arm — xử lý ở finally theo prefs.enabled).
    prefs = await NotificationPrefsStore().read();
    if (!prefs.enabled) {
      await AppLog.i(src, LogTags.digest, 'bản tin đang TẮT → bỏ mốc này');
      return;
    }

    final coords = await resolveBackgroundCoords(source: src);
    if (coords == null) return; // vẫn re-arm ở finally cho ngày mai.

    // Cycle lock: bản tin fetch dữ liệu tươi nên cũng phải xếp hàng với chu kỳ
    // nền, không thì hai isolate cùng mở DB (`database is locked`).
    await CycleLock.runGuarded(src, () async {
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
    // Đặt lại alarm cho ngày mai (one-shot không tự lặp). Chỉ khi bản tin còn bật
    // VÀ mốc (index) này vẫn tồn tại trong danh sách. Bọc try riêng để lỗi hiển
    // thị không chặn việc re-arm.
    try {
      final p = prefs ?? await NotificationPrefsStore().read();
      final index = id - NotificationIds.digestBase;
      if (p.enabled && index >= 0 && index < p.times.length) {
        await scheduleDigestSlot(id, p.times[index], source: src);
      } else {
        await AppLog.i(
          src,
          LogTags.digest,
          'KHÔNG re-arm mốc này',
          data: {
            'id': id,
            'lý do': p.enabled ? 'mốc đã bị xoá khỏi cài đặt' : 'bản tin đã tắt',
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
    await AppLog.flush();
  }
}
