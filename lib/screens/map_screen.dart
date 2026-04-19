// lib/screens/map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';
import '../theme.dart';

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
      appBar: AppBar(
        title: const Text('Live Location'),
        actions: [
          IconButton(
            icon: Icon(
              _followDevice ? Icons.my_location : Icons.location_searching,
              color: _followDevice ? AppTheme.primary : AppTheme.textSecondary,
            ),
            onPressed: () {
              setState(() => _followDevice = !_followDevice);
              if (_followDevice && _lastData != null) {
                _animateToDevice(_lastData!);
              }
            },
            tooltip: 'Follow device',
          ),
        ],
      ),
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
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.fallDetected
                        ? AppTheme.danger.withOpacity(0.8)
                        : AppTheme.primary.withOpacity(0.8),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Center(
                    child: Icon(
                      data.fallDetected ? Icons.warning : Icons.location_on,
                      color: Colors.white,
                      size: 16,
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

              // ─── Info Card at bottom ──────────────────────────────────
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: data == null
                      ? const Center(
                          child: Text('Waiting for device GPS data...',
                              style:
                                  TextStyle(color: AppTheme.textSecondary)))
                      : Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on,
                                  color: AppTheme.primary),
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
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Lat: ${data.latitude.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                  Text(
                                    'Lng: ${data.longitude.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    data.lastSeenLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: data.deviceOnline
                                    ? AppTheme.success.withOpacity(0.1)
                                    : AppTheme.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                data.deviceOnline ? 'Live' : 'Last Known',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: data.deviceOnline
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                ),
                              ),
                            )
                          ],
                        ),
                ),
              ),

              // ─── Loading indicator ────────────────────────────────────
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
