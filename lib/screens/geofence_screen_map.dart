// lib/screens/geofence_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geofence_model.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class GeofenceScreen extends StatefulWidget {
  final String userId;
  final String deviceId;

  const GeofenceScreen({
    required this.userId,
    required this.deviceId,
    Key? key,
  }) : super(key: key);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofences'),
        elevation: 0,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<GeofenceModel>>(
        stream: firebase.getGeofences(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final geofences = snapshot.data ?? [];

          return Column(
            children: [
              // Map section
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
                    ),
                    // Draw existing geofence center points
                    CircleLayer(
                      circles: [
                        for (final geofence in geofences)
                          CircleMarker(
                            point: LatLng(
                              geofence.latitude,
                              geofence.longitude,
                            ),
                            radius: 6,
                            useRadiusInMeter: false,
                            color: geofence.enabled
                                ? AppTheme.primary.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.2),
                            borderStrokeWidth: 2,
                            borderColor: geofence.enabled
                                ? AppTheme.primary
                                : Colors.grey,
                          ),
                      ],
                    ),
                    // Draw geofence radius circles
                    CircleLayer(
                      circles: [
                        for (final geofence in geofences)
                          CircleMarker(
                            point: LatLng(
                              geofence.latitude,
                              geofence.longitude,
                            ),
                            radius: geofence.radiusMeters,
                            useRadiusInMeter: true,
                            color: geofence.enabled
                                ? AppTheme.primary.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderStrokeWidth: 1.5,
                            borderColor: geofence.enabled
                                ? AppTheme.primary.withOpacity(0.6)
                                : Colors.grey.withOpacity(0.4),
                          ),
                      ],
                    ),
                    // Draw fence being created
                    if (_isCreatingFence && _currentFenceCenter != null) ...[
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _currentFenceCenter!,
                            radius: _currentFenceRadius,
                            useRadiusInMeter: true,
                            color: AppTheme.primary.withOpacity(0.15),
                            borderStrokeWidth: 2,
                            borderColor: AppTheme.primary,
                          ),
                          CircleMarker(
                            point: _currentFenceCenter!,
                            radius: 8,
                            useRadiusInMeter: false,
                            color: AppTheme.primary,
                            borderStrokeWidth: 0,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Geofence list or creation panel
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
          ? FloatingActionButton(
              onPressed: () => setState(() {
                _isCreatingFence = true;
                _currentFenceCenter = null;
                _currentFenceRadius = 500;
                _fenceName = '';
              }),
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildCreationPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Geofence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _fenceName,
              decoration: InputDecoration(
                label: const Text('Fence Name'),
                hintText: 'Home, Office, etc.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                prefixIcon: const Icon(Icons.location_on),
              ),
              onChanged: (name) => _fenceName = name,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_currentFenceCenter!.latitude.toStringAsFixed(6)}° N, ${_currentFenceCenter!.longitude.toStringAsFixed(6)}° E',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Radius',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentFenceRadius.toInt()}m',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _currentFenceRadius,
                  min: 100,
                  max: 5000,
                  divisions: 49,
                  label: '${_currentFenceRadius.toInt()}m',
                  onChanged: (value) =>
                      setState(() => _currentFenceRadius = value),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '100m',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '5000m',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _isCreatingFence = false;
                      _currentFenceCenter = null;
                      _fenceName = '';
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _fenceName.isEmpty || _currentFenceCenter == null
                        ? null
                        : () => _saveFence(),
                    child: const Text('Save Fence'),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No geofences yet',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create one',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
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
          const SnackBar(content: Text('Geofence created')),
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
        title: const Text('Delete Geofence'),
        content: Text('Delete "${geofence.name}"?'),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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

// ─── Geofence Card Widget ──────────────────────────────────────────────────
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and toggle row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        geofence.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: geofence.enabled
                              ? AppTheme.textPrimary
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${geofence.radiusMeters.toInt()}m radius',
                        style: TextStyle(
                          fontSize: 13,
                          color: geofence.enabled
                              ? AppTheme.textSecondary
                              : Colors.grey.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: geofence.enabled,
                  onChanged: (_) => onToggle(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Coordinates display
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lat: ${geofence.latitude.toStringAsFixed(6)}°',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lng: ${geofence.longitude.toStringAsFixed(6)}°',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
