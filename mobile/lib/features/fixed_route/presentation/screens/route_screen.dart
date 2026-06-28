import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../location/presentation/providers/location_provider.dart';
import '../../domain/entities/poi.dart';
import '../providers/route_provider.dart';
import '../widgets/poi_visuals.dart';

/// Màn lộ trình cố định: chạm bản đồ để thêm điểm, quét tiện ích (POI) dọc
/// lộ trình bằng OpenStreetMap/Overpass (miễn phí).
class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({super.key});

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  final _mapController = MapController();

  // Bộ lọc quét.
  final Set<PoiType> _selectedTypes = {PoiType.gasStation, PoiType.restaurant};
  int _radius = 500;

  static const _fallbackCenter = LatLng(21.0278, 105.8342); // Hà Nội

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routeControllerProvider);
    final controller = ref.read(routeControllerProvider.notifier);
    final coordsAsync = ref.watch(currentLocationProvider);

    final initialCenter = coordsAsync.maybeWhen(
      data: (c) => LatLng(c.latitude, c.longitude),
      orElse: () => state.points.isNotEmpty
          ? LatLng(state.points.first.latitude, state.points.first.longitude)
          : _fallbackCenter,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lộ trình & tiện ích'),
        actions: [
          IconButton(
            tooltip: 'Về vị trí của tôi',
            icon: const Icon(Icons.my_location),
            onPressed: () => coordsAsync.whenData((c) {
              _mapController.move(LatLng(c.latitude, c.longitude), 15);
            }),
          ),
          IconButton(
            tooltip: 'Xoá lộ trình',
            icon: const Icon(Icons.delete_outline),
            onPressed: state.points.isEmpty ? null : controller.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildMap(state, controller, initialCenter)),
          _buildControls(context, state, controller),
          Expanded(flex: 2, child: _buildBottom(context, state)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => coordsAsync.whenData(
          (c) => controller.addPoint(c.latitude, c.longitude,
              label: 'Vị trí hiện tại'),
        ),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Thêm vị trí'),
      ),
    );
  }

  Widget _buildMap(
    RouteState state,
    RouteController controller,
    LatLng initialCenter,
  ) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14,
        onTap: (_, latlng) =>
            controller.addPoint(latlng.latitude, latlng.longitude),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.katocast.app',
        ),
        if (state.points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  for (final p in state.points) LatLng(p.latitude, p.longitude),
                ],
                strokeWidth: 4,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Điểm lộ trình (đánh số).
            for (var i = 0; i < state.points.length; i++)
              Marker(
                point: LatLng(
                    state.points[i].latitude, state.points[i].longitude),
                width: 30,
                height: 30,
                child: _RouteDot(index: i + 1),
              ),
            // POI tìm được.
            for (final poi in state.pois)
              Marker(
                point: LatLng(poi.latitude, poi.longitude),
                width: 32,
                height: 32,
                child: Icon(
                  poiIcon(poi.type),
                  color: poiColor(poi.type),
                  size: 28,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    RouteState state,
    RouteController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final t in PoiType.values)
                FilterChip(
                  label: Text(poiLabel(t)),
                  avatar: Icon(poiIcon(t), size: 18, color: poiColor(t)),
                  selected: _selectedTypes.contains(t),
                  onSelected: (sel) => setState(() {
                    sel ? _selectedTypes.add(t) : _selectedTypes.remove(t);
                  }),
                ),
            ],
          ),
          Row(
            children: [
              const Text('Bán kính'),
              Expanded(
                child: Slider(
                  value: _radius.toDouble(),
                  min: 200,
                  max: 2000,
                  divisions: 9,
                  label: '$_radius m',
                  onChanged: (v) => setState(() => _radius = v.round()),
                ),
              ),
              Text('$_radius m'),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (state.scanning || _selectedTypes.isEmpty)
                  ? null
                  : () => controller.scan(
                        radiusMeters: _radius,
                        types: _selectedTypes.toList(),
                      ),
              icon: state.scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(state.scanning ? 'Đang quét…' : 'Quét tiện ích'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(BuildContext context, RouteState state) {
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(state.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (state.points.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chạm lên bản đồ hoặc nhấn "Thêm vị trí" để tạo lộ trình, '
            'rồi quét tiện ích dọc đường.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state.pois.isEmpty) {
      return Center(
        child: Text(
          '${state.points.length} điểm lộ trình. Chọn loại tiện ích và nhấn Quét.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: state.pois.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final poi = state.pois[i];
        return ListTile(
          dense: true,
          leading: Icon(poiIcon(poi.type), color: poiColor(poi.type)),
          title: Text(poi.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(poiLabel(poi.type)),
          trailing: Text('${poi.distanceToRouteMeters.round()} m'),
          onTap: () => _mapController.move(
            LatLng(poi.latitude, poi.longitude),
            16,
          ),
        );
      },
    );
  }
}

/// Chấm tròn đánh số cho điểm lộ trình.
class _RouteDot extends StatelessWidget {
  final int index;
  const _RouteDot({required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.onPrimary, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
