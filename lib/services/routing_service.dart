// lib/services/routing_service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Fetches road-following routes from the public OSRM demo server (free, no
/// API key). `profile` is `driving` or `foot`.
class RoutingService {
  Future<RouteResult?> fetchRoute(
    LatLng origin,
    LatLng dest, {
    String profile = 'driving',
  }) async {
    // OSRM expects `lng,lat` ordering.
    final url = 'https://router.project-osrm.org/route/v1/$profile/'
        '${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}'
        '?overview=full&geometries=geojson';

    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') return null;

    final routes = json['routes'] as List;
    if (routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List;

    final points = coords
        .map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ))
        .toList();

    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}
