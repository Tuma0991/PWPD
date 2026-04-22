// lib/screens/map_screen.dart

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
  final _firebase = FirebaseService();
  final MapController _mapController = MapController();
  DeviceData? _lastData;
  bool _followDevice = true;

  static const LatLng _defaultCenter = LatLng(10.3157, 123.8854); // Cebu, PH

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<DeviceData>(
        stream: _firebase.listenToDeviceData(widget.deviceId),
        builder: (context, snapshot) {
          final data = snapshot.data;
          _lastData = data;

          List<Marker> markers = [];
          if (data != null && data.latitude != 0) {
            markers.add(
              Marker(
                point: LatLng(data.latitude, data.longitude),
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.fallDetected
                        ? const Color(0xFFE53935)
                        : const Color(0xFF1565C0),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: (data.fallDetected
                                ? const Color(0xFFE53935)
                                : const Color(0xFF1565C0))
                            .withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      data.fallDetected ? Icons.warning : Icons.person_pin,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            );

            if (_followDevice) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _animateToDevice(data);
              });
            }
          }

          return Stack(
            children: [
              // Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: data != null && data.latitude != 0
                      ? LatLng(data.latitude, data.longitude)
                      : _defaultCenter,
                  initialZoom: 16,
                  onPositionChanged: (mapPosition, hasGesture) {
                    if (hasGesture && _followDevice) {
                      setState(() => _followDevice = false);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.pwpd',
                    maxZoom: 19,
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),

              // ─── Top App Bar overlay ─────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1565C0).withOpacity(0.95),
                        const Color(0xFF1565C0).withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Row(
                        children: [
                          const Icon(Icons.map, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Live Location',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          // Follow toggle button
                          GestureDetector(
                            onTap: () {
                              setState(() => _followDevice = !_followDevice);
                              if (_followDevice && _lastData != null) {
                                _animateToDevice(_lastData!);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: _followDevice
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _followDevice
                                        ? Icons.my_location
                                        : Icons.location_searching,
                                    size: 15,
                                    color: _followDevice
                                        ? const Color(0xFF1565C0)
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _followDevice ? 'Following' : 'Free',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _followDevice
                                          ? const Color(0xFF1565C0)
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ─── Bottom info card ────────────────────────────────────
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1565C0).withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: data == null
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Waiting for device GPS data...',
                              style: TextStyle(
                                  color: Color(0xFF6B7A99), fontSize: 13),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0).withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.location_on,
                                  color: Color(0xFF1565C0), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Device Location',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A2340),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Lat: ${data.latitude.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7A99)),
                                  ),
                                  Text(
                                    'Lng: ${data.longitude.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7A99)),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    data.lastSeenLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF9EA8C2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: data.deviceOnline
                                    ? const Color(0xFF2E7D32).withOpacity(0.10)
                                    : const Color(0xFFE53935).withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: data.deviceOnline
                                      ? const Color(0xFF2E7D32).withOpacity(0.3)
                                      : const Color(0xFFE53935).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: data.deviceOnline
                                          ? const Color(0xFF43A047)
                                          : const Color(0xFFE53935),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    data.deviceOnline ? 'Live' : 'Last Known',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: data.deviceOnline
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFE53935),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // ─── Loading indicator ───────────────────────────────────
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }

  void _animateToDevice(DeviceData data) {
    if (data.latitude == 0 && data.longitude == 0) return;
    _mapController.move(
      LatLng(data.latitude, data.longitude),
      16,
    );
  }
}