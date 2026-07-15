import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/failures.dart';
import '../../../../shared/widgets/app_drawer.dart';
import '../../../../shared/widgets/app_error_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/permission_denied_widget.dart';
import '../../../location/domain/entities/place.dart';
import '../../../location/presentation/providers/location_provider.dart';
import '../../data/repositories/weather_repository_impl.dart';
import '../../domain/usecases/build_advisories.dart';
import '../providers/weather_provider.dart';
import '../widgets/advisory_card.dart';
import '../widgets/condition_card.dart';
import '../widgets/current_card.dart';
import '../widgets/digest_settings_card.dart';
import '../widgets/hourly_list.dart';
import '../widgets/rain_alert_banner.dart';

/// Màn hình chính: thời tiết hiện tại + cảnh báo mưa + dự báo theo giờ.
class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(weatherProvider);

    final placeAsync = ref.watch(currentPlaceProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('KatoAssistant 🐾'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_outlined, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    placeAsync.maybeWhen(
                      data: (place) =>
                          place?.shortLabel ?? 'Không xác định vị trí',
                      orElse: () => 'Đang xác định vị trí…',
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: weatherAsync.when(
          loading: () => const LoadingWidget(message: 'Đang lấy thời tiết...'),
          error: (e, _) => _buildError(context, ref, e),
          data: (data) {
            final rain = ref.watch(rainStatusProvider);
            final condition = ref.watch(weatherConditionProvider);
            final offline = ref.watch(connectivityStatusProvider).maybeWhen(
                  data: (online) => !online,
                  orElse: () => false,
                );
            final advisories = condition != null
                ? const BuildAdvisories().call(
                    current: data.current,
                    condition: condition,
                    rain: rain,
                  )
                : const <Advisory>[];
            return ListView(
              children: [
                if (data.isStale)
                  _staleBadge(context, data.fetchedAt, offline),
                _locationHeader(context, placeAsync),
                if (rain != null) RainAlertBanner(status: rain),
                if (condition != null) ConditionCard(condition: condition),
                AdvisoryCard(advisories: advisories),
                CurrentWeatherCard(
                    current: data.current, hourly: data.hourly),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Dự báo theo giờ',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                HourlyList(hourly: data.hourly, minutely: data.minutely),
                const DigestSettingsCard(),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    // Invalidate cả vị trí (để thử lại quyền), địa danh, lẫn thời tiết.
    ref.invalidate(currentLocationProvider);
    ref.invalidate(currentPlaceProvider);
    ref.invalidate(weatherProvider);
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    // Quyền bị từ chối → hướng dẫn người dùng, không hiện lỗi kỹ thuật.
    if (error is PermissionFailure) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: PermissionDeniedWidget(
              failure: error,
              onRetry: () => _refresh(ref),
              onOpenSettings: () =>
                  ref.read(permissionServiceProvider).openSettings(),
            ),
          ),
        ],
      );
    }
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: AppErrorWidget(error: error, onRetry: () => _refresh(ref)),
        ),
      ],
    );
  }

  /// Header địa điểm ĐẦY ĐỦ (không bị cắt như trên AppBar) để người dùng biết
  /// app đang lấy thời tiết đúng nơi.
  Widget _locationHeader(BuildContext context, AsyncValue<Place?> placeAsync) {
    final label = placeAsync.maybeWhen(
      data: (place) => place?.fullLabel ?? 'Không xác định vị trí',
      orElse: () => 'Đang xác định vị trí…',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.place_outlined,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staleBadge(BuildContext context, DateTime fetchedAt, bool offline) {
    final local = fetchedAt.toLocal();
    // Đồng hồ máy có thể vừa nhảy lùi (NTP) khiến fetchedAt thành TƯƠNG LAI →
    // đừng hiện mốc giờ tương lai gây hoang mang; coi như "vừa cập nhật".
    final isFuture = local.isAfter(DateTime.now());
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    // Offline thật → nói rõ offline; còn online mà dữ liệu cũ → đang làm mới.
    final msg = offline
        ? (isFuture
            ? 'Đang offline — dữ liệu vừa cập nhật'
            : 'Đang offline — hiển thị dữ liệu lúc $time')
        : (isFuture
            ? 'Vừa cập nhật · đang làm mới…'
            : 'Dữ liệu lúc $time · đang làm mới…');
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(8),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
