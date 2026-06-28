import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_palettes.dart';

/// Cài đặt giao diện của người dùng (lưu trong SharedPreferences).
class ThemeSettings {
  /// Sáng / Tối / Theo hệ thống.
  final ThemeMode mode;

  /// Id bảng màu chọn sẵn (khi không dùng dynamic/weather).
  final String paletteId;

  /// Material You — lấy màu động theo hình nền hệ thống (Android 12+).
  final bool useDynamicColor;

  /// Đổi tông màu theo tình hình thời tiết hiện tại.
  final bool weatherAdaptive;

  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.paletteId = kDefaultPaletteId,
    this.useDynamicColor = false,
    this.weatherAdaptive = false,
  });

  ThemeSettings copyWith({
    ThemeMode? mode,
    String? paletteId,
    bool? useDynamicColor,
    bool? weatherAdaptive,
  }) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      paletteId: paletteId ?? this.paletteId,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      weatherAdaptive: weatherAdaptive ?? this.weatherAdaptive,
    );
  }
}

/// Quản lý + lưu trữ cài đặt giao diện. Đọc 1 lần lúc khởi tạo, ghi mỗi khi đổi.
class ThemeController extends StateNotifier<ThemeSettings> {
  ThemeController() : super(const ThemeSettings()) {
    _load();
  }

  static const _kMode = 'theme_mode';
  static const _kPalette = 'theme_palette_id';
  static const _kDynamic = 'theme_use_dynamic';
  static const _kWeather = 'theme_weather_adaptive';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt(_kMode);
    state = ThemeSettings(
      mode: (modeIdx != null && modeIdx >= 0 && modeIdx < ThemeMode.values.length)
          ? ThemeMode.values[modeIdx]
          : ThemeMode.system,
      paletteId: prefs.getString(_kPalette) ?? kDefaultPaletteId,
      useDynamicColor: prefs.getBool(_kDynamic) ?? false,
      weatherAdaptive: prefs.getBool(_kWeather) ?? false,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMode, mode.index);
  }

  Future<void> setPalette(String paletteId) async {
    state = state.copyWith(paletteId: paletteId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPalette, paletteId);
  }

  Future<void> setUseDynamicColor(bool value) async {
    state = state.copyWith(useDynamicColor: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamic, value);
  }

  Future<void> setWeatherAdaptive(bool value) async {
    state = state.copyWith(weatherAdaptive: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeather, value);
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeSettings>(
  (ref) => ThemeController(),
);
