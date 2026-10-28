// lib/models/device_data.dart

class DeviceData {
  /// Fallback staleness (seconds) when the device does not report a heartbeat
  /// interval. Covers the slowest (resting) heartbeat with margin.
  static const int _fallbackStaleThresholdSeconds = 900;

  /// Multiplier applied to the device's heartbeat interval. The device is
  /// considered offline once it has missed this many heartbeats.
  static const double _staleMultiplier = 2.5;

  final double latitude;
  final double longitude;
  final double accelX;
  final double accelY;
  final double accelZ;
  final bool fallDetected;
  final int timestamp;

  /// Heartbeat interval reported by the device, in seconds. The v2 firmware
  /// sends a heartbeat every 120 s (active) / 300 s (resting) instead of a
  /// live 2 s stream, so offline detection must scale with this value.
  final int hbIntervalS;

  /// Device-reported power/activity mode: "resting", "active", or "emergency".
  final String mode;

  DeviceData({
    required this.latitude,
    required this.longitude,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.fallDetected,
    required this.timestamp,
    this.hbIntervalS = 0,
    this.mode = '',
  });

  /// Seconds after the last heartbeat before the device is considered offline.
  int get onlineStaleThresholdSeconds {
    if (hbIntervalS > 0) {
      return (hbIntervalS * _staleMultiplier).ceil();
    }
    return _fallbackStaleThresholdSeconds;
  }

  /// Device is online only if the last timestamp is recent enough.
  /// No longer depends on a separate "online" flag — if the ESP32 is
  /// sending heartbeats, the timestamp is fresh. If it's off, it goes stale.
  bool get deviceOnline {
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
      hbIntervalS: (map['hbIntervalS'] ?? 0).toInt(),
      mode: map['mode'] ?? '',
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
    int? hbIntervalS,
    String? mode,
  }) {
    return DeviceData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      fallDetected: fallDetected ?? this.fallDetected,
      timestamp: timestamp ?? this.timestamp,
      hbIntervalS: hbIntervalS ?? this.hbIntervalS,
      mode: mode ?? this.mode,
    );
  }
}