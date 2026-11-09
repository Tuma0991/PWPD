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
/// `driving` or `foot`. Both modes use the driving road network for the route
/// geometry (the fastest/nearest road route to the device); walking mode only
/// rescales the ETA to a typical walking pace.
class RoutingService {
  static const String _drivingUrl = 'https://routing.openstreetmap.de/routed-car';
  static const double _walkingMetersPerSecond = 1.39; // ~5 km/h

  Future<RouteResult?> fetchRoute(
    LatLng origin,
    LatLng dest, {
    String profile = 'driving',
  }) async {
    // OSRM expects `lng,lat` ordering.
    final url = '$_drivingUrl/route/v1/driving/'
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

    final distanceMeters = (route['distance'] as num).toDouble();
    final durationSeconds = profile == 'foot'
        ? distanceMeters / _walkingMetersPerSecond
        : (route['duration'] as num).toDouble();

    return RouteResult(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }
}
