import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../location/presentation/providers/location_provider.dart';
import '../../domain/repositories/news_repository.dart';
import '../providers/news_provider.dart';

/// Màn Bản đồ & Tin tức: bản đồ OSM (kèm lớp mưa OWM nếu có API key) +
/// danh sách tin thời tiết/cảnh báo (RSS).
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  static const _fallbackCenter = LatLng(21.0278, 105.8342); // Hà Nội

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordsAsync = ref.watch(currentLocationProvider);
    final newsAsync = ref.watch(newsProvider);

    final center = coordsAsync.maybeWhen(
      data: (c) => LatLng(c.latitude, c.longitude),
      orElse: () => _fallbackCenter,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Bản đồ & Tin tức')),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildMap(context, center, coordsAsync)),
          Expanded(flex: 2, child: _buildNews(context, ref, newsAsync)),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context, LatLng center, dynamic coordsAsync) {
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 11),
      children: [
        TileLayer(
          urlTemplate: AppConfig.osmTileUrl,
          userAgentPackageName: AppConfig.tilePackageName,
        ),
        // Lớp phủ lượng mưa từ OpenWeatherMap (dùng lại API key đã có).
        if (AppConfig.hasApiKey)
          TileLayer(
            urlTemplate: AppConfig.owmPrecipTileUrl,
            userAgentPackageName: AppConfig.tilePackageName,
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 40,
              height: 40,
              child: Icon(
                Icons.my_location,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNews(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<NewsItem>> newsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.article_outlined, size: 18),
              const SizedBox(width: 6),
              Text('Tin thời tiết',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Làm mới',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(newsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: newsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Không tải được tin tức.')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('Chưa có tin nào.'));
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final n = items[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.cloud_outlined),
                    title:
                        Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: n.publishedAt != null
                        ? Text(_fmtDate(n.publishedAt!))
                        : null,
                    trailing: const Icon(Icons.open_in_new, size: 16),
                    onTap: () => _open(n.url),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}
