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

/// Fetches road-following routes from OSRM (free, no API key). `profile` is
/// `driving` or `foot`.
class RoutingService {
  // FOSSGIS-hosted OSRM instances. A single OSRM server serves only one
  // routing profile, so each profile needs its own host — the shared demo
  // server (`router.project-osrm.org`) only serves the car profile and returns
  // identical car results for every profile requested.
  static const Map<String, String> _baseUrl = {
    'driving': 'https://routing.openstreetmap.de/routed-car',
    'foot': 'https://routing.openstreetmap.de/routed-foot',
  };

  Future<RouteResult?> fetchRoute(
    LatLng origin,
    LatLng dest, {
    String profile = 'driving',
  }) async {
    final base = _baseUrl[profile] ?? _baseUrl['driving']!;
    // OSRM expects `lng,lat` ordering.
    final url = '$base/route/v1/$profile/'
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
