// lib/models/device_data.dart

class DeviceData {
  /// Number of seconds after the last device update before we consider it offline.
  ///
  /// Adjust this value to change how aggressively the app marks a device offline.
  /// For example:
  /// - 30 seconds for very strict live status
  /// - 120 seconds for a more tolerant connection indicator
  /// - 300 seconds for slower update intervals
  static const int onlineStaleThresholdSeconds = 120;

  final double latitude;
  final double longitude;
  final double accelX;
  final double accelY;
  final double accelZ;
  final bool fallDetected;
  final int timestamp;
  final bool rawOnline;

  DeviceData({
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.fallDetected,
    required this.timestamp,
    required this.rawOnline,
  });

  /// The app now considers the device online only when the device is reporting
  /// online and the last timestamp is recent enough.
  bool get deviceOnline {
    if (!rawOnline) return false;
    if (timestamp <= 0) return false;
    final ageMillis = DateTime.now().millisecondsSinceEpoch - timestamp;
    return ageMillis <= onlineStaleThresholdSeconds * 1000;
  }

  bool get isOnlineStale {
    if (timestamp <= 0) return true;
    final ageMillis = DateTime.now().millisecondsSinceEpoch - timestamp;
    return ageMillis > onlineStaleThresholdSeconds * 1000;
  }

  int get ageMillis {
    if (timestamp <= 0) return 0;
    return DateTime.now().millisecondsSinceEpoch - timestamp;
  }

  Duration get age => Duration(milliseconds: ageMillis);

  String get lastSeenLabel {
    if (timestamp <= 0) return 'Last seen unknown';
    if (age.inSeconds < 10) return 'Last seen just now';
    if (age.inMinutes < 1) return 'Last seen ${age.inSeconds}s ago';
    if (age.inHours < 1) return 'Last seen ${age.inMinutes}m ago';
    if (age.inDays < 1) return 'Last seen ${age.inHours}h ago';
    return 'Last seen ${age.inDays}d ago';
  }

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
      rawOnline: map['online'] ?? false,
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
    bool? rawOnline,
  }) {
    return DeviceData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      fallDetected: fallDetected ?? this.fallDetected,
      timestamp: timestamp ?? this.timestamp,
      rawOnline: rawOnline ?? this.rawOnline,
    );
  }
}
