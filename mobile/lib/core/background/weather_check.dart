import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/alerts/data/alert_state_store.dart';
import '../../features/alerts/data/digest_scheduler.dart';
import '../../features/alerts/data/notification_prefs_store.dart';
import '../../features/alerts/domain/usecases/build_weather_alerts.dart';
import '../../features/announcements/data/announcement_prefs_store.dart';
import '../../features/announcements/data/announcement_scheduler.dart';
import '../../features/weather/data/datasources/weather_local_datasource.dart';
import '../../features/weather/data/datasources/weather_remote_datasource.dart';
import '../../features/weather/data/repositories/weather_repository_impl.dart';
import '../../features/weather/domain/entities/uv_advice.dart';
import '../../features/weather/domain/entities/weather.dart';
import '../../features/weather/domain/entities/weather_condition.dart';
import '../../features/weather/domain/usecases/analyze_rain.dart';
import '../../features/weather/domain/usecases/detect_env_change.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/log_entry.dart';
import '../diagnostics/log_tags.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import 'background_location.dart';
import 'background_prefs.dart';

/// Khoá SharedPreferences: lần dọn cache thời tiết gần nhất (ms epoch).
const String _kLastPurgeMsKey = 'weather_cache_last_purge_ms';

/// LÕI kiểm tra thời tiết nền — dùng CHUNG cho cả 3 lớp trigger:
/// foreground service (chính), alarm exact backstop, và WorkManager.
/// Chạy trong isolate riêng nên tự dựng dependency, KHÔNG dùng Riverpod.
///
/// GUARD QUOTA: OWM 4.0 tốn 3 call/refresh, giới hạn 1000/ngày. Hàm chỉ gọi API
/// khi cache đã cũ hơn (chu kỳ − 1'); cache còn tươi thì dùng lại. Lưu ý:
/// `repo.getWeather` luôn gọi remote khi online, nên guard PHẢI nằm ở đây.
///
/// [source] = lớp trigger đang gọi (xem [LogSource]) — chỉ dùng cho nhật ký, để
/// đọc log biết được LỚP NÀO chạy lúc nào.
///
/// [db] cho phép caller TRUYỀN VÀO một `AppDatabase` đang mở để dùng chung.
/// Trước đây mỗi tick mở 2 `AppDatabase` (một cho re-assert ghi chú, một ở đây),
/// mỗi lần `NativeDatabase.createInBackground` lại spawn một isolate phụ → 4
/// isolate DB mỗi 15' khi FG và alarm cùng chạy. Dùng chung một handle giảm cả
/// rác tiến trình lẫn nguy cơ `database is locked`.
///
/// Trả về [WeatherData] đã dùng (để foreground service dựng nội dung thông báo
/// thường trực), hoặc null nếu không có dữ liệu.
Future<WeatherData?> runWeatherCheck({
  String source = LogSource.ui,
  AppDatabase? db,
}) async {
  final coords = await resolveBackgroundCoords(source: source);
  if (coords == null) return null;

  final ownsDb = db == null;
  final database = db ?? AppDatabase();
  final api = ApiClient.create();
  try {
    final local = WeatherLocalDataSource(database);

    // Dọn cache cũ: chỉ TỐI ĐA 1 LẦN/NGÀY. Trước đây chạy mỗi chu kỳ — một câu
    // DELETE vô ích ở 95% lần gọi, mà lại là một lượt GHI làm tăng tranh chấp
    // khoá DB. Bọc try riêng: lỗi dọn dẹp KHÔNG được làm hỏng cả chu kỳ (trước
    // đây nó nằm ngoài try nên một lỗi `database is locked` ở đây làm mất luôn
    // dữ liệu + thông báo của chu kỳ, và không để lại dấu vết nào).
    await _purgeCacheIfDue(local, source);

    final repo = WeatherRepositoryImpl(
      WeatherRemoteDataSource(api),
      local,
      NetworkInfoImpl(Connectivity()),
      logSource: source,
    );

    final interval = await BackgroundPrefsStore().intervalMinutes();
    final gapMinutes = interval > 1 ? interval - 1 : interval;
    WeatherData? data;
    try {
      final cached = await repo.getCachedWeather(coords);
      if (cached != null && cached.age.inMinutes < gapMinutes) {
        data = cached;
        await AppLog.i(
          source,
          LogTags.source,
          'DÙNG CACHE (guard quota) — không gọi API',
          data: {
            'tuổi': '${cached.age.inMinutes}p',
            'ngưỡng': '${gapMinutes}p',
          },
        );
      } else {
        await AppLog.i(
          source,
          LogTags.source,
          'GỌI API — cache thiếu hoặc đã cũ',
          data: {
            'tuổi': cached == null ? 'chưa có' : '${cached.age.inMinutes}p',
            'ngưỡng': '${gapMinutes}p',
          },
        );
        final result = await repo.getWeather(coords);
        data = result.fold((_) => null, (d) => d);
      }
    } catch (e, st) {
      await AppLog.e(
        source,
        LogTags.db,
        'lỗi khi đọc cache/lấy dữ liệu (có thể do DB bị khoá giữa các isolate)',
        error: e,
        stack: st,
      );
      return null;
    }

    if (data == null) {
      await AppLog.w(
        source,
        LogTags.fetch,
        'không có dữ liệu (offline và chưa có cache) → bỏ chu kỳ',
      );
      return null;
    }

    // Các side-effect (sinh cảnh báo + lập lịch) bọc try RIÊNG để một lỗi ở đây
    // KHÔNG làm mất `data` — foreground service cần `data` để cập nhật thông báo
    // thường trực.
    try {
      if (data.age.inMinutes <= AppConfig.alertMaxDataAgeMinutes) {
        await _maybeAlert(data, source);
      } else {
        await AppLog.w(
          source,
          LogTags.skip,
          'KHÔNG sinh cảnh báo: dữ liệu quá cũ',
          data: {
            'tuổi': '${data.age.inMinutes}p',
            'trần': '${AppConfig.alertMaxDataAgeMinutes}p',
          },
        );
      }
    } catch (e, st) {
      await AppLog.e(source, LogTags.notify, 'lỗi khi sinh cảnh báo',
          error: e, stack: st);
    }

    // Bản tin hằng ngày + poll tin: đảm bảo alarm khớp cài đặt (idempotent, có
    // throttle bên trong nên gọi mỗi chu kỳ không gây ANR).
    try {
      final dp = await NotificationPrefsStore().read();
      await scheduleDigests(dp, source: source);
    } catch (e, st) {
      await AppLog.e(source, LogTags.digest, 'lỗi lập lịch bản tin',
          error: e, stack: st);
    }
    try {
      final ap = await AnnouncementPrefsStore().read();
      await scheduleAnnouncementCheck(ap, source: source);
    } catch (e, st) {
      await AppLog.e(source, LogTags.announce, 'lỗi lập lịch poll tin',
          error: e, stack: st);
    }

    return data;
  } finally {
    api.close();
    if (ownsDb) {
      try {
        await database.close();
      } catch (e, st) {
        await AppLog.e(source, LogTags.db, 'lỗi đóng DB', error: e, stack: st);
      }
    }
  }
}

/// Phân tích mưa/môi trường rồi phát cảnh báo nếu cần, ghi log ĐẦY ĐỦ quyết định
/// (phát cái gì, hoặc bỏ qua vì lý do gì).
///
/// Chuỗi đọc-tính-ghi `AlertStateStore` phải chạy trong cùng một cycle lock (do
/// lớp trigger giữ) — nếu không, hai isolate cùng đọc trạng thái cũ rồi cùng
/// phát một cảnh báo, người dùng nghe thông báo hai lần.
Future<void> _maybeAlert(WeatherData data, String source) async {
  final rain = const AnalyzeRain().call(data);
  final env = const DetectEnvChange().call(data);
  final condition = WeatherCondition.classify(
    data.current.conditionId,
    rainMmH: data.current.rain1h,
  );

  // Ghi cả SỐ LIỆU THÔ đã dùng để kết luận. Không có phần này thì không thể
  // đối chiếu khi app nói "đang mưa" mà ngoài trời chỉ âm u — chính là ca người
  // dùng phản ánh. Ngưỡng cũng in kèm để thấy ngay vì sao ra kết luận đó.
  final nowcastNow = data.minutely.isNotEmpty
      ? data.minutely.first.precipitationMmH
      : null;
  await AppLog.i(
    source,
    LogTags.analyze,
    'phân tích xong',
    data: {
      'pha': rain.phase.name,
      'tình hình': condition.label,
      'nguồn': rain.fromMinutely ? 'nowcast 15p' : 'dự báo giờ',
      // --- số liệu thô ---
      'nowcast bây giờ': nowcastNow == null
          ? 'không có'
          : '${nowcastNow.toStringAsFixed(2)} mm/h',
      'ngưỡng ĐANG mưa': '${AppConfig.rainNowThresholdMmH} mm/h '
          '× ${AppConfig.rainNowSustainedSlots} mốc',
      'mưa 1h quan trắc': '${data.current.rain1h.toStringAsFixed(2)} mm',
      'mã điều kiện OWM': data.current.conditionId ?? 'không có',
      'tuổi dữ liệu': '${data.age.inMinutes}p',
      // --- kết luận ---
      if (rain.changeAt != null) 'mốc': _hhmm(rain.changeAt!),
      if (rain.rainEndsAt != null) 'tạnh': _hhmm(rain.rainEndsAt!),
      if (rain.probabilityPct != null) 'xác suất': '${rain.probabilityPct}%',
      if (rain.segments.length >= 2) 'số đoạn mưa': rain.segments.length,
      if (env.hasStrongChange)
        'môi trường': 'Δt ${env.tempDeltaC.toStringAsFixed(1)}°C · '
            'Δẩm ${env.humidityDeltaPct.toStringAsFixed(0)}%',
    },
  );

  final store = AlertStateStore();
  final prev = await store.read();
  if (prev.expired) {
    await AppLog.w(
      source,
      LogTags.skip,
      'trạng thái cảnh báo lần trước ĐÃ QUÁ CŨ → coi như khởi đầu mới '
      '(app vừa bị ngắt một khoảng dài)',
      data: {'tuổi': '${prev.age!.inMinutes}p', 'trần': '${AlertStateStore.maxAge.inMinutes}p'},
    );
  }

  final out = const BuildWeatherAlerts().call(
    rain: rain,
    condition: condition,
    env: env,
    previousPhase: prev.phase,
    previousCategory: prev.category,
    previousChangeAt: prev.changeAt,
    previousNotifiedAt: prev.notifiedAt,
    envAlreadyNotified: prev.envNotified,
    // Lượng mưa quan trắc THẬT: dùng để không phát thông báo "đang có mưa nhỏ"
    // chỉ vì mã điều kiện OWM, khi phân tích mưa đã kết luận trời khô.
    observedRain1hMm: data.current.rain1h,
  );

  if (out.alerts.isEmpty) {
    await AppLog.i(
      source,
      LogTags.skip,
      'KHÔNG báo — chưa có gì đổi so với lần trước',
      data: {
        'pha trước': prev.phase?.name ?? 'chưa có',
        'pha nay': out.newPhase.name,
        if (prev.changeAt != null) 'mốc đã báo': _hhmm(prev.changeAt!),
        if (prev.notifiedAt != null) 'báo lúc': _hhmm(prev.notifiedAt!),
      },
    );
  } else {
    final notif = NotificationService();
    await notif.init();
    for (final a in out.alerts) {
      await notif.show(id: a.id, title: a.title, body: a.body);
      await AppLog.i(
        source,
        LogTags.notify,
        'ĐÃ BÁO: ${a.title}',
        data: {'id': a.id, 'nội dung': a.body},
      );
    }
  }

  await store.write(
    phase: out.newPhase,
    category: out.newCategory,
    changeAt: out.newChangeAt,
    notifiedAt: out.newNotifiedAt,
    envNotified: out.envNotified,
  );
}

/// Dọn cache thời tiết cũ, tối đa 1 lần/ngày. Lỗi được ghi log và bỏ qua.
Future<void> _purgeCacheIfDue(
  WeatherLocalDataSource local,
  String source,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // `reload()` vì mỗi isolate giữ một bản cache riêng — không reload thì
    // isolate sống lâu (foreground service) sẽ dọn lại mỗi chu kỳ.
    await prefs.reload();
    final lastMs = prefs.getInt(_kLastPurgeMsKey) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const dayMs = 24 * 60 * 60 * 1000;
    if (lastMs != 0 && nowMs - lastMs < dayMs) return;

    await local.purgeOlderThan(
      const Duration(days: AppConfig.cacheMaxAgeDays),
    );
    await prefs.setInt(_kLastPurgeMsKey, nowMs);
    await AppLog.i(source, LogTags.db, 'đã dọn cache thời tiết cũ (1 lần/ngày)');
  } catch (e, st) {
    await AppLog.w(
      source,
      LogTags.db,
      'dọn cache thất bại (bỏ qua, không ảnh hưởng chu kỳ)',
      data: {'err': e.toString()},
    );
    assert(() {
      // ignore: avoid_print
      print('purgeCache: $e\n$st');
      return true;
    }());
  }
}

/// Nội dung ngắn cho thông báo thường trực của foreground service, ví dụ
/// "🌤️ 33°C · Trời nắng · UV 8 · cập nhật 14:35".
String foregroundStatusText(WeatherData data) {
  final c = data.current;
  final condition = WeatherCondition.classify(c.conditionId, rainMmH: c.rain1h);
  final tempStr = c.tempC != null ? '${c.tempC!.round()}°C' : '—';
  final uvi = c.uvi;
  final uvStr = uvi != null ? ' · UV ${UvAdvice.classify(uvi).level}' : '';
  // Dữ liệu chưa làm mới được (fetch fail → cache cũ) HOẶC quá tuổi cảnh báo →
  // báo trung thực "dữ liệu cũ" thay vì để giờ `fetchedAt` cũ trông như mới.
  final stale = data.fromCacheFallback ||
      data.age.inMinutes > AppConfig.alertMaxDataAgeMinutes;
  final staleStr = stale ? ' · ⚠️ dữ liệu cũ' : '';
  return '${condition.emoji} $tempStr · ${condition.label}'
      '$uvStr · cập nhật ${_hhmm(data.fetchedAt)}$staleStr';
}

/// Định dạng giờ "HH:mm" theo giờ máy (thủ công, không cần `intl`).
String _hhmm(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
