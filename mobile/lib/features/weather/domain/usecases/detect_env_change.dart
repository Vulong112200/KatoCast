import '../../../../core/config/app_config.dart';
import '../entities/weather.dart';

/// Phát hiện thay đổi mạnh nhiệt độ/độ ẩm giữa hiện tại và vài giờ tới
/// (để nhắc "chú ý không gian sống và thú cưng").
class EnvChange {
  final bool hasStrongChange;
  final double tempDeltaC;
  final double humidityDeltaPct;
  const EnvChange({
    required this.hasStrongChange,
    required this.tempDeltaC,
    required this.humidityDeltaPct,
  });

  static const none =
      EnvChange(hasStrongChange: false, tempDeltaC: 0, humidityDeltaPct: 0);
}

class DetectEnvChange {
  const DetectEnvChange();

  /// So hiện tại với cực trị trong 3 giờ tới.
  EnvChange call(WeatherData data) {
    if (data.hourly.isEmpty) return EnvChange.none;

    final window = data.hourly.take(3);
    final curT = data.current.tempC;
    final curH = data.current.humidity.toDouble();

    var maxTempDelta = 0.0;
    var maxHumDelta = 0.0;
    for (final h in window) {
      final dt = (h.tempC - curT).abs();
      final dh = (h.humidity - curH).abs();
      if (dt > maxTempDelta) maxTempDelta = dt;
      if (dh > maxHumDelta) maxHumDelta = dh;
    }

    final strong = maxTempDelta >= AppConfig.strongTempDeltaC ||
        maxHumDelta >= AppConfig.strongHumidityDeltaPct;

    return EnvChange(
      hasStrongChange: strong,
      tempDeltaC: maxTempDelta,
      humidityDeltaPct: maxHumDelta,
    );
  }
}
