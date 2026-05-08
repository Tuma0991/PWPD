// lib/models/geofence_model.dart

import 'package:latlong2/latlong.dart';

class GeofenceModel {
  final String id;
  final String userId;
  final String name;
  final List<LatLng> vertices;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? updatedAt;

  GeofenceModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.vertices,
    required this.enabled,
    required this.createdAt,
    this.updatedAt,
  });

  /// Convert model to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'vertices': vertices
          .map((v) => {'lat': v.latitude, 'lng': v.longitude})
          .toList(),
      'enabled': enabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt ?? createdAt,
    };
  }

  /// Create model from Firestore map
  static GeofenceModel fromMap(String id, Map<String, dynamic> map) {
    final verticesList = map['vertices'] as List? ?? [];
    final vertices = verticesList.map((v) {
      final vertex = Map<String, dynamic>.from(v);
      return LatLng(
        (vertex['lat'] ?? 0).toDouble(),
        (vertex['lng'] ?? 0).toDouble(),
      );
    }).toList();

    return GeofenceModel(
      id: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? 'Unknown Zone',
      vertices: vertices,
      enabled: map['enabled'] ?? true,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as dynamic).toDate()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as dynamic).toDate()
          : null,
    );
  }

  GeofenceModel copyWith({
    String? id,
    String? userId,
    String? name,
    List<LatLng>? vertices,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GeofenceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      vertices: vertices ?? this.vertices,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'GeofenceModel(id: $id, name: $name, vertices: ${vertices.length}, enabled: $enabled)';
}
