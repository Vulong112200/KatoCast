import 'package:flutter/material.dart';

import '../../domain/entities/poi.dart';

/// Nhãn tiếng Việt cho loại tiện ích.
String poiLabel(PoiType type) {
  switch (type) {
    case PoiType.restaurant:
      return 'Nhà hàng';
    case PoiType.gasStation:
      return 'Cây xăng';
    case PoiType.cafe:
      return 'Cà phê';
    case PoiType.supermarket:
      return 'Siêu thị';
  }
}

/// Icon minh hoạ cho loại tiện ích.
IconData poiIcon(PoiType type) {
  switch (type) {
    case PoiType.restaurant:
      return Icons.restaurant;
    case PoiType.gasStation:
      return Icons.local_gas_station;
    case PoiType.cafe:
      return Icons.local_cafe;
    case PoiType.supermarket:
      return Icons.shopping_cart;
  }
}

/// Màu marker theo loại tiện ích.
Color poiColor(PoiType type) {
  switch (type) {
    case PoiType.restaurant:
      return const Color(0xFFEF6C00); // cam
    case PoiType.gasStation:
      return const Color(0xFF2E7D32); // lục
    case PoiType.cafe:
      return const Color(0xFF6D4C41); // nâu
    case PoiType.supermarket:
      return const Color(0xFF1565C0); // xanh dương
  }
}
