// lib/models/device_data.dart

class DeviceData {
  final double latitude;
  final double longitude;
  final double accelX;
  final double accelY;
  final double accelZ;
  final bool fallDetected;
  final int timestamp;
  final bool deviceOnline;

  DeviceData({
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.fallDetected,
    required this.timestamp,
    required this.deviceOnline,
  });

  factory DeviceData.fromMap(Map<String, dynamic> map) {
    final gps = Map<String, dynamic>.from(map['gps'] ?? {});
    final accel = Map<String, dynamic>.from(map['accelerometer'] ?? {});
    return DeviceData(
      latitude: (gps['lat'] ?? 0.0).toDouble(),
      longitude: (gps['lng'] ?? 0.0).toDouble(),
      accelX: (accel['x'] ?? 0.0).toDouble(),
      accelY: (accel['y'] ?? 0.0).toDouble(),
      accelZ: (accel['z'] ?? 0.0).toDouble(),
      fallDetected: map['fallDetected'] ?? false,
      timestamp: map['timestamp'] ?? 0,
      deviceOnline: map['online'] ?? false,
    );
  }

  // Magnitude of acceleration — used to detect falls
  double get accelMagnitude =>
      (accelX * accelX + accelY * accelY + accelZ * accelZ).abs();

  DeviceData copyWith({
    double? latitude,
    double? longitude,
    double? accelX,
    double? accelY,
    double? accelZ,
    bool? fallDetected,
    int? timestamp,
    bool? deviceOnline,
  }) {
    return DeviceData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      fallDetected: fallDetected ?? this.fallDetected,
      timestamp: timestamp ?? this.timestamp,
      deviceOnline: deviceOnline ?? this.deviceOnline,
    );
  }
}
