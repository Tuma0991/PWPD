// lib/screens/geofence_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geofence_model.dart';
import '../services/firebase_service.dart';

class GeofenceScreen extends StatefulWidget {
  final String userId;
  final String deviceId;

  const GeofenceScreen({
    super.key,
    required this.userId,
    required this.deviceId,
  });

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final firebase = FirebaseService();
  final MapController _mapController = MapController();
  
  LatLng? _currentFenceCenter;
  double _currentFenceRadius = 500;
  bool _isCreatingFence = false;
  String _fenceName = '';

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1565C0),
          elevation: 0,
          title: const Text('Geofences',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: const Center(
          child: Text(
            'Please log in to use geofences',
            style: TextStyle(color: Color(0xFF6B7A99)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Geofences',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<GeofenceModel>>(
        stream: firebase.getGeofences(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Color(0xFFE53935)),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading geofences',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7A99)),
                    ),
                  ],
                ),
              ),
            );
          }

          final geofences = snapshot.data ?? [];

          return Column(
            children: [
              // Map hint bar
              if (_isCreatingFence && _currentFenceCenter == null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFF1565C0),
                  child: const Row(
                    children: [
                      Icon(Icons.touch_app, color: Colors.white70, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Tap on the map to place your geofence center',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

              Expanded(
                flex: 2,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(0, 0),
                    initialZoom: 13,
                    onTap: (tapPosition, point) {
                      if (_isCreatingFence) {
                        setState(() => _currentFenceCenter = point);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pwpd.application',
                    ),
                    CircleLayer(
                      circles: [
                        for (final geofence in geofences)
                          CircleMarker(
                            point: LatLng(geofence.latitude, geofence.longitude),
                            radius: 6,
                            useRadiusInMeter: false,
                            color: geofence.enabled
                                ? const Color(0xFF1565C0).withOpacity(0.3)
                                : Colors.grey.withOpacity(0.2),
                            borderStrokeWidth: 2,
                            borderColor: geofence.enabled
                                ? const Color(0xFF1565C0)
                                : Colors.grey,
                          ),
                      ],
                    ),
                    CircleLayer(
                      circles: [
                        for (final geofence in geofences)
                          CircleMarker(
                            point: LatLng(geofence.latitude, geofence.longitude),
                            radius: geofence.radiusMeters,
                            useRadiusInMeter: true,
                            color: geofence.enabled
                                ? const Color(0xFF1565C0).withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderStrokeWidth: 1.5,
                            borderColor: geofence.enabled
                                ? const Color(0xFF1565C0).withOpacity(0.6)
                                : Colors.grey.withOpacity(0.4),
                          ),
                      ],
                    ),
                    if (_isCreatingFence && _currentFenceCenter != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _currentFenceCenter!,
                            radius: _currentFenceRadius,
                            useRadiusInMeter: true,
                            color: const Color(0xFF1565C0).withOpacity(0.15),
                            borderStrokeWidth: 2,
                            borderColor: const Color(0xFF1565C0),
                          ),
                          CircleMarker(
                            point: _currentFenceCenter!,
                            radius: 8,
                            useRadiusInMeter: false,
                            color: const Color(0xFF1565C0),
                            borderStrokeWidth: 0,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: _isCreatingFence && _currentFenceCenter != null
                    ? _buildCreationPanel()
                    : _buildGeofenceList(geofences),
              ),
            ],
          );
        },
      ),
      floatingActionButton: !_isCreatingFence
          ? FloatingActionButton.extended(
              onPressed: () => setState(() {
                _isCreatingFence = true;
                _currentFenceCenter = null;
                _currentFenceRadius = 500;
                _fenceName = '';
              }),
              backgroundColor: const Color(0xFF1565C0),
              elevation: 4,
              icon: const Icon(Icons.add_location_alt, color: Colors.white),
              label: const Text(
                'Add Fence',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            )
          : null,
    );
  }

  Widget _buildCreationPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_location_alt,
                      color: Color(0xFF1565C0), size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'New Geofence',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2340),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: _fenceName,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A2340)),
              decoration: InputDecoration(
                labelText: 'Fence Name',
                hintText: 'Home, School, Office...',
                labelStyle:
                    const TextStyle(color: Color(0xFF6B7A99), fontSize: 13),
                prefixIcon: const Icon(Icons.location_on,
                    color: Color(0xFF1565C0), size: 20),
                filled: true,
                fillColor: const Color(0xFFF7F9FF),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFFDDE3F0), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF1565C0), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
              ),
              onChanged: (name) => _fenceName = name,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF1565C0).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop,
                      size: 16, color: Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Location',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7A99)),
                      ),
                      Text(
                        '${_currentFenceCenter!.latitude.toStringAsFixed(5)}°, ${_currentFenceCenter!.longitude.toStringAsFixed(5)}°',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Radius',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2340),
                    fontSize: 13,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_currentFenceRadius.toInt()}m',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _currentFenceRadius,
              min: 100,
              max: 5000,
              divisions: 49,
              activeColor: const Color(0xFF1565C0),
              label: '${_currentFenceRadius.toInt()}m',
              onChanged: (value) => setState(() => _currentFenceRadius = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _isCreatingFence = false;
                      _currentFenceCenter = null;
                      _fenceName = '';
                    }),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDDE3F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                          color: Color(0xFF6B7A99),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _fenceName.isEmpty || _currentFenceCenter == null
                        ? null
                        : () => _saveFence(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Save Fence',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeofenceList(List<GeofenceModel> geofences) {
    if (geofences.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4FF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off,
                  size: 36,
                  color: Color(0xFF1565C0),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No geofences yet',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2340),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap "Add Fence" to create a safe zone',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Text(
                  'Saved Zones',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2340),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${geofences.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemCount: geofences.length,
              itemBuilder: (context, index) {
                final geofence = geofences[index];
                return _GeofenceCard(
                  geofence: geofence,
                  onEdit: () => _editGeofence(geofence),
                  onDelete: () => _showDeleteDialog(geofence),
                  onToggle: () => _toggleGeofence(geofence),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFence() async {
    if (_currentFenceCenter == null || _fenceName.isEmpty) return;

    try {
      final geofence = GeofenceModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: widget.userId,
        name: _fenceName,
        latitude: _currentFenceCenter!.latitude,
        longitude: _currentFenceCenter!.longitude,
        radiusMeters: _currentFenceRadius,
        enabled: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await firebase.addGeofence(widget.userId, geofence);
      final geofences = await firebase.getGeofences(widget.userId).first;
      await firebase.syncGeofencesToDevice(widget.deviceId, geofences);

      setState(() {
        _isCreatingFence = false;
        _currentFenceCenter = null;
        _fenceName = '';
        _currentFenceRadius = 500;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Geofence created successfully!'),
            backgroundColor: const Color(0xFF2E7D32),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _editGeofence(GeofenceModel geofence) async {
    setState(() {
      _isCreatingFence = true;
      _currentFenceCenter = LatLng(geofence.latitude, geofence.longitude);
      _currentFenceRadius = geofence.radiusMeters;
      _fenceName = geofence.name;
    });

    _mapController.move(_currentFenceCenter!, 15);
  }

  void _showDeleteDialog(GeofenceModel geofence) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Geofence',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Delete "${geofence.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _deleteGeofence(geofence.id);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGeofence(GeofenceModel geofence) async {
    try {
      final updated = geofence.copyWith(enabled: !geofence.enabled);
      await firebase.updateGeofence(widget.userId, geofence.id, updated);
      final geofences = await firebase.getGeofences(widget.userId).first;
      await firebase.syncGeofencesToDevice(widget.deviceId, geofences);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteGeofence(String id) async {
    try {
      await firebase.deleteGeofence(widget.userId, id);
      final geofences = await firebase.getGeofences(widget.userId).first;
      await firebase.syncGeofencesToDevice(widget.deviceId, geofences);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }
}

// ─── Geofence Card Widget ─────────────────────────────────────────────────────

class _GeofenceCard extends StatelessWidget {
  final GeofenceModel geofence;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _GeofenceCard({
    required this.geofence,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final color = geofence.enabled
        ? const Color(0xFF1565C0)
        : const Color(0xFF9EA8C2);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.location_on, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      geofence.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: geofence.enabled
                            ? const Color(0xFF1A2340)
                            : const Color(0xFF9EA8C2),
                      ),
                    ),
                    Text(
                      '${geofence.radiusMeters.toInt()}m radius',
                      style: TextStyle(
                        fontSize: 12,
                        color: geofence.enabled
                            ? const Color(0xFF6B7A99)
                            : Colors.grey.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: geofence.enabled,
                onChanged: (_) => onToggle(),
                activeColor: const Color(0xFF1565C0),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.pin_drop,
                    size: 13, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Text(
                  '${geofence.latitude.toStringAsFixed(5)}°, ${geofence.longitude.toStringAsFixed(5)}°',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF6B7A99),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.edit_outlined,
                    size: 16, color: Color(0xFF1565C0)),
                label: const Text(
                  'Edit',
                  style: TextStyle(
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Color(0xFFE53935)),
                label: const Text(
                  'Delete',
                  style: TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}