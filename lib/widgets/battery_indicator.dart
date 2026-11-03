// lib/widgets/battery_indicator.dart

import 'package:flutter/material.dart';

/// Returns a stable, per-device battery percentage in [55, 100].
///
/// The ESP32 firmware does not report battery yet, so the app shows a
/// deterministic fake value (distinct per device) until real telemetry lands.
int simulatedBatteryPercent(String deviceId) {
  var hash = 0;
  for (final code in deviceId.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return 55 + hash % 46;
}

Color batteryColor(int percent) {
  if (percent <= 20) return const Color(0xFFE53935);
  if (percent <= 50) return const Color(0xFFF57C00);
  return const Color(0xFF2E7D32);
}

IconData batteryIcon(int percent) {
  if (percent >= 90) return Icons.battery_full;
  if (percent >= 70) return Icons.battery_6_bar;
  if (percent >= 55) return Icons.battery_5_bar;
  if (percent >= 40) return Icons.battery_4_bar;
  if (percent >= 25) return Icons.battery_3_bar;
  if (percent >= 10) return Icons.battery_2_bar;
  return Icons.battery_1_bar;
}
