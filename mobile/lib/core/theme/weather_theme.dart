import 'package:flutter/material.dart';

import '../../features/weather/domain/entities/weather_condition.dart';

/// Màu seed gợi ý theo tình hình thời tiết hiện tại — dùng khi người dùng bật
/// "Đổi màu theo thời tiết". Nắng → ấm, mây → trung tính, mưa → xanh lạnh,
/// dông/bão → tối/đậm.
Color seedForCategory(WeatherCategory category) {
  switch (category) {
    case WeatherCategory.clear:
      return const Color(0xFFFFA000); // hổ phách nắng
    case WeatherCategory.fewClouds:
      return const Color(0xFF42A5F5); // xanh trời nhạt
    case WeatherCategory.cloudy:
    case WeatherCategory.overcast:
      return const Color(0xFF607D8B); // xám xanh
    case WeatherCategory.fog:
      return const Color(0xFF78909C); // xám sương
    case WeatherCategory.drizzle:
    case WeatherCategory.lightRain:
    case WeatherCategory.moderateRain:
      return const Color(0xFF26A69A); // xanh ngọc mưa nhẹ
    case WeatherCategory.heavyRain:
      return const Color(0xFF1565C0); // xanh dương đậm
    case WeatherCategory.thunderstorm:
      return const Color(0xFF5E35B1); // tím dông
    case WeatherCategory.severeStorm:
      return const Color(0xFFC62828); // đỏ cảnh báo
    case WeatherCategory.snow:
      return const Color(0xFF90CAF9); // xanh băng
    case WeatherCategory.other:
      return const Color(0xFF2E6FB7);
  }
}
