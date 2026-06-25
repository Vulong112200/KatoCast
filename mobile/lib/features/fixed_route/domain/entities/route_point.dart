/// Một điểm trên lộ trình cố định (vd nơi làm việc → nhà).
class RoutePoint {
  final int? id;
  final String routeId;
  final double latitude;
  final double longitude;
  final int seq;
  final String? label;

  const RoutePoint({
    this.id,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.seq,
    this.label,
  });
}
