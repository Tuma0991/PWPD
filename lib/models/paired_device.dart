import 'package:cloud_firestore/cloud_firestore.dart';

/// A wearable device paired to the signed-in user. Stored as a document under
/// `users/{uid}/devices/{deviceId}` (the same doc also holds the wearer's
/// name/photo — see [DeviceSettingsModel]).
class PairedDevice {
  final String deviceId;
  final String deviceName;
  final String wearerName;
  final DateTime? addedAt;

  const PairedDevice({
    required this.deviceId,
    required this.deviceName,
    this.wearerName = '',
    this.addedAt,
  });

  factory PairedDevice.fromMap(String id, Map<String, dynamic> map) {
    return PairedDevice(
      deviceId: id,
      deviceName: (map['deviceName'] ?? '') as String? ?? '',
      wearerName: (map['name'] ?? '') as String? ?? '',
      addedAt: (map['addedAt'] as Timestamp?)?.toDate(),
    );
  }

  String get displayName => deviceName.isNotEmpty ? deviceName : deviceId;
}
