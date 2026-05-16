// lib/screens/map_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';

class MapScreen extends StatefulWidget {
  final String deviceId;
  const MapScreen({super.key, required this.deviceId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirebaseService _firebase = FirebaseService();
  final MapController _mapController = MapController();

  LatLng? _deviceLocation;
  String _lastSeenLabel = 'Unknown';
  bool _isFollowing = true;
  bool _hasMovedOnce = false;
  DeviceData? _latestData;

  StreamSubscription<DeviceData>? _dataSub;

  static const LatLng _defaultCenter = LatLng(10.0989, 122.8708); // Himamaylan City, Negros Occidental

  /// ESP32 sends near-zero coords (e.g. 0.033, 0.300) when GPS has no fix.
  /// Only treat as real if at least one axis is outside a ±0.5° dead-zone.
  static bool _isValidGps(double lat, double lng) =>
      lat.abs() > 0.5 || lng.abs() > 0.5;

  @override
  void initState() {
    super.initState();
    _dataSub = _firebase.listenToDeviceData(widget.deviceId).listen((data) {
      if (!mounted) return;
      setState(() {
        _latestData = data;
        if (_isValidGps(data.latitude, data.longitude)) {
          _deviceLocation = LatLng(data.latitude, data.longitude);
          _lastSeenLabel = data.lastSeenLabel;
          if (_isFollowing) {
            // Move camera to follow device
            try {
              if (_hasMovedOnce) {
                _mapController.move(_deviceLocation!, _mapController.camera.zoom);
              } else {
                _mapController.move(_deviceLocation!, 15.0);
                _hasMovedOnce = true;
              }
            } catch (_) {}
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceId.isEmpty) return _buildNoDevice();

    final center = _deviceLocation ?? _defaultCenter;
    final hasLocation = _deviceLocation != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.map, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Live Location',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          // Follow toggle
          GestureDetector(
            onTap: () {
              setState(() => _isFollowing = !_isFollowing);
              if (_isFollowing && _deviceLocation != null) {
                _mapController.move(_deviceLocation!, 15.0);
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isFollowing
                    ? Colors.white.withOpacity(0.20)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isFollowing ? 'Following' : 'Free',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: hasLocation ? 15.0 : 14.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _isFollowing) {
                  setState(() => _isFollowing = false);
                }
              },
            ),
            children: [
              // ── Tile Layer (OpenStreetMap) ─────────────────────────────
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.pwpd',
                maxZoom: 19,
                // Required: OSM rejects requests without a valid User-Agent
                additionalOptions: const {
                  'User-Agent': 'pwpd/1.0 (Flutter; Android)',
                },
              ),

              // ── Device Marker ─────────────────────────────────────────
              if (hasLocation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _deviceLocation!,
                      width: 56,
                      height: 56,
                      child: const _DeviceMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // ── Bottom Info Card ──────────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF1565C0),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device Location',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2340),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasLocation
                              ? 'Lat: ${_deviceLocation!.latitude.toStringAsFixed(6)}\n'
                                  'Lng: ${_deviceLocation!.longitude.toStringAsFixed(6)}'
                              : 'No GPS signal yet',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7A99),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lastSeenLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9EA8C2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: hasLocation
                          ? (_latestData?.deviceOnline == true
                              ? const Color(0xFF43A047).withOpacity(0.10)
                              : const Color(0xFFE53935).withOpacity(0.08))
                          : const Color(0xFF9EA8C2).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasLocation
                            ? (_latestData?.deviceOnline == true
                                ? const Color(0xFF43A047).withOpacity(0.3)
                                : const Color(0xFFE53935).withOpacity(0.3))
                            : const Color(0xFF9EA8C2).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: hasLocation
                                ? (_latestData?.deviceOnline == true
                                    ? const Color(0xFF43A047)
                                    : const Color(0xFFE53935))
                                : const Color(0xFF9EA8C2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          hasLocation
                              ? (_latestData?.deviceOnline == true
                                  ? 'Live'
                                  : 'Last Known')
                              : 'No Signal',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: hasLocation
                                ? (_latestData?.deviceOnline == true
                                    ? const Color(0xFF43A047)
                                    : const Color(0xFFE53935))
                                : const Color(0xFF9EA8C2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── No location overlay ───────────────────────────────────────
          if (!hasLocation)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.gps_off,
                          size: 36,
                          color: Color(0xFF9EA8C2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Waiting for GPS signal…',
                          style: TextStyle(
                            color: Color(0xFF6B7A99),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),

      // ── Re-center FAB ──────────────────────────────────────────────────
      floatingActionButton: hasLocation && !_isFollowing
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF1565C0),
              onPressed: () {
                setState(() => _isFollowing = true);
                _mapController.move(_deviceLocation!, 15.0);
              },
              child: const Icon(Icons.my_location, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildNoDevice() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.map, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Live Location',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ],
        ),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 48, color: Color(0xFF9EA8C2)),
            SizedBox(height: 16),
            Text('No device configured',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7A99))),
            SizedBox(height: 8),
            Text('Set up your device from the Home tab',
                style: TextStyle(fontSize: 13, color: Color(0xFF9EA8C2))),
          ],
        ),
      ),
    );
  }
}

// ─── Device Marker Widget ─────────────────────────────────────────────────────

class _DeviceMarker extends StatelessWidget {
  const _DeviceMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulse ring
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
        ),
        // Inner dot
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}