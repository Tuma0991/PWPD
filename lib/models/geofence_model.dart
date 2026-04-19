// lib/models/geofence_model.dart

class GeofenceModel {
  final String id;
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? updatedAt;

  GeofenceModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.enabled,
    required this.createdAt,
    this.updatedAt,
  });

  /// Convert model to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'enabled': enabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt ?? createdAt,
    };
  }

  /// Create model from Firestore map
  static GeofenceModel fromMap(String id, Map<String, dynamic> map) {
    return GeofenceModel(
      id: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? 'Unknown Zone',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      radiusMeters: (map['radiusMeters'] ?? 500).toDouble(),
      enabled: map['enabled'] ?? true,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as dynamic).toDate()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as dynamic).toDate()
          : null,
    );
  }

  /// Copy with method
  GeofenceModel copyWith({
    String? id,
    String? userId,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GeofenceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'GeofenceModel(id: $id, name: $name, lat: $latitude, lng: $longitude, radius: $radiusMeters m, enabled: $enabled)';
}
