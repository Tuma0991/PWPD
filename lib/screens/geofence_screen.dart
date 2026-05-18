// lib/screens/geofence_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/device_data.dart';
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
  final FirebaseService _firebase = FirebaseService();
  final MapController _mapController = MapController();

  // ─── Drawing state ──────────────────────────────────────────────────────────
  bool _isDrawing = false;
  List<LatLng> _vertices = [];
  String _fenceName = '';
  GeofenceModel? _editingGeofence;

  // ─── Device GPS tracking ────────────────────────────────────────────────────
  StreamSubscription<DeviceData>? _dataSub;
  LatLng? _deviceLocation;

  static bool _isValidGps(double lat, double lng) =>
      lat.abs() > 0.5 || lng.abs() > 0.5;

  static const LatLng _defaultCenter = LatLng(10.0989, 122.8708);

  @override
  void initState() {
    super.initState();
    if (widget.deviceId.isNotEmpty) {
      _dataSub = _firebase.listenToDeviceData(widget.deviceId).listen((data) {
        if (!mounted) return;
        if (_isValidGps(data.latitude, data.longitude)) {
          final newLoc = LatLng(data.latitude, data.longitude);
          // Don't rebuild if location hasn't changed — the ESP32 pushes
          // every 2s, which would otherwise flicker the entire map.
          if (_deviceLocation != newLoc) {
            setState(() => _deviceLocation = newLoc);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

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
        title: Row(
          children: [
            Icon(
              _isDrawing ? Icons.edit_location_alt : Icons.location_on,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _isDrawing
                  ? (_editingGeofence != null ? 'Edit Polygon' : 'Draw Polygon')
                  : 'Geofences',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        leading: _isDrawing
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _cancelDrawing,
              )
            : null,
      ),
      body: StreamBuilder<List<GeofenceModel>>(
        stream: _firebase.getGeofences(widget.userId),
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
                    const Text('Error loading geofences',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A2340))),
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

          // Move camera to polygon when editing
          if (_isDrawing && _vertices.isNotEmpty && !_hasMovedToPolygon) {
            _hasMovedToPolygon = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitMapToVertices();
            });
          }

          return Column(
            children: [
              // ── Hint bar ──────────────────────────────────────────────
              if (_isDrawing)
                _buildDrawingHint(),

              // ── Map ───────────────────────────────────────────────────
              Expanded(
                flex: _isDrawing ? 3 : 2,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 15,
                    onTap: _isDrawing
                        ? (tapPosition, point) {
                            setState(() => _vertices.add(point));
                          }
                        : null,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pwpd.application',
                      additionalOptions: const {
                        'User-Agent': 'pwpd/1.0 (Flutter; Android)',
                      },
                    ),

                    // ── Device position marker (view mode) ──────────
                    if (!_isDrawing && _deviceLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _deviceLocation!,
                            width: 48,
                            height: 48,
                            child: const _DeviceLocationMarker(),
                          ),
                        ],
                      ),

                    // ── Saved geofence polygons (view mode) ─────────
                    if (!_isDrawing)
                      PolygonLayer(
                        polygons: [
                          for (final gf in geofences)
                            if (gf.vertices.length >= 3)
                              Polygon(
                                points: [...gf.vertices, gf.vertices.first],
                                color: gf.enabled
                                    ? const Color(0xFF1565C0).withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.05),
                                borderColor: gf.enabled
                                    ? const Color(0xFF1565C0)
                                    : Colors.grey,
                                borderStrokeWidth: gf.enabled ? 2.0 : 1.0,
                                isFilled: true,
                              ),
                        ],
                      ),

                    // ── Drawing polygon ──────────────────────────────
                    if (_isDrawing && _vertices.isNotEmpty)
                      MarkerLayer(
                        markers: _vertices.asMap().entries.map((entry) {
                          return Marker(
                            point: entry.value,
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    // ── Polygon fill (3+ vertices) ──────────────────
                    if (_isDrawing && _vertices.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: [..._vertices, _vertices.first],
                            color: const Color(0xFF1565C0).withOpacity(0.10),
                            borderColor: const Color(0xFF1565C0),
                            borderStrokeWidth: 2.5,
                            isFilled: true,
                          ),
                        ],
                      ),

                    // ── Connecting lines ───────────────────────────────
                    if (_isDrawing && _vertices.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [
                              ..._vertices,
                              if (_vertices.length >= 3) _vertices.first,
                            ],
                            color: const Color(0xFF1565C0),
                            strokeWidth: 2.5,
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // ── Bottom panel ──────────────────────────────────────────
              Expanded(
                flex: 1,
                child: _isDrawing
                    ? _buildDrawingPanel()
                    : _buildGeofenceList(geofences),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _isDrawing
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startDrawing(),
              backgroundColor: const Color(0xFF1565C0),
              elevation: 4,
              icon: const Icon(Icons.add_location_alt, color: Colors.white),
              label: const Text(
                'Add Polygon',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
    );
  }

  // ─── Drawing helpers ────────────────────────────────────────────────────────

  bool _hasMovedToPolygon = false;

  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _editingGeofence = null;
      _vertices = [];
      _fenceName = '';
      _hasMovedToPolygon = false;
    });
  }

  void _cancelDrawing() {
    setState(() {
      _isDrawing = false;
      _editingGeofence = null;
      _vertices = [];
      _fenceName = '';
      _hasMovedToPolygon = false;
    });
  }

  void _undoLastVertex() {
    setState(() {
      if (_vertices.isNotEmpty) {
        _vertices = [..._vertices]..removeLast();
      }
    });
  }

  void _clearAllVertices() {
    setState(() {
      _vertices = [];
      _hasMovedToPolygon = false;
    });
  }

  void _fitMapToVertices() {
    if (_vertices.isEmpty) return;
    if (_vertices.length == 1) {
      _mapController.move(_vertices.first, 17);
      return;
    }
    final bounds = LatLngBounds.fromPoints(_vertices);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {
      _mapController.move(_vertices.first, 16);
    }
  }

  Widget _buildDrawingHint() {
    final count = _vertices.length;
    String text;
    if (count == 0) {
      text = 'Tap on the map to place your first vertex';
    } else if (count < 3) {
      text = 'Place ${3 - count} more point${3 - count > 1 ? 's' : ''} to form a polygon';
    } else {
      text = '$count points — tap to add more or save your polygon';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1565C0),
      child: Row(
        children: [
          const Icon(Icons.touch_app, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Drawing panel (bottom sheet area) ──────────────────────────────────────

  Widget _buildDrawingPanel() {
    final canSave = _fenceName.isNotEmpty && _vertices.length >= 3;

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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _editingGeofence != null
                        ? Icons.edit_location_alt
                        : Icons.add_location_alt,
                    color: const Color(0xFF1565C0),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _editingGeofence != null ? 'Edit Polygon' : 'New Polygon',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2340),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Name field
            TextFormField(
              initialValue: _fenceName,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A2340)),
              decoration: InputDecoration(
                labelText: 'Polygon Name',
                hintText: 'Home, School, Park...',
                labelStyle: const TextStyle(
                    color: Color(0xFF6B7A99), fontSize: 13),
                prefixIcon: const Icon(Icons.label_outline,
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
            const SizedBox(height: 10),

            // Vertex count
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _vertices.length >= 3
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _vertices.length >= 3
                        ? Icons.check_circle
                        : Icons.info_outline,
                    size: 18,
                    color: _vertices.length >= 3
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFF57C00),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _vertices.length >= 3
                        ? '${_vertices.length} vertices — polygon valid'
                        : '${_vertices.length} of 3 minimum vertices placed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _vertices.length >= 3
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFF57C00),
                    ),
                  ),
                ],
              ),
            ),

            // Vertex list (scrollable if many)
            if (_vertices.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _vertices.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final v = _vertices[index];
                    return Container(
                      width: 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF1565C0).withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Point ${index + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${v.latitude.toStringAsFixed(4)}°',
                            style: const TextStyle(
                              fontSize: 9, fontFamily: 'monospace'),
                          ),
                          Text(
                            '${v.longitude.toStringAsFixed(4)}°',
                            style: const TextStyle(
                              fontSize: 9, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                // Undo last
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _vertices.isEmpty ? null : _undoLastVertex,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDDE3F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.undo, size: 16,
                        color: Color(0xFF6B7A99)),
                    label: const Text(
                      'Undo',
                      style: TextStyle(
                        color: Color(0xFF6B7A99),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Clear all
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _vertices.isEmpty ? null : _clearAllVertices,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDDE3F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16,
                        color: Color(0xFFE53935)),
                    label: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelDrawing,
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSave ? _savePolygon : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(
                      _editingGeofence != null
                          ? 'Update Polygon'
                          : 'Save Polygon',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

  // ─── Geofence list (view mode) ──────────────────────────────────────────────

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
                'Tap "Add Polygon" to draw a custom zone',
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

  // ─── Save / Edit / Delete / Toggle ──────────────────────────────────────────

  Future<void> _savePolygon() async {
    if (_vertices.length < 3 || _fenceName.isEmpty) return;

    try {
      if (_editingGeofence != null) {
        // Update existing
        final updated = _editingGeofence!.copyWith(
          name: _fenceName,
          vertices: List.from(_vertices),
          updatedAt: DateTime.now(),
        );
        await _firebase.updateGeofence(
            widget.userId, _editingGeofence!.id, updated);
      } else {
        // Create new
        final geofence = GeofenceModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: widget.userId,
          name: _fenceName,
          vertices: List.from(_vertices),
          enabled: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _firebase.addGeofence(widget.userId, geofence);
      }

      // Sync to device
      final geofences =
          await _firebase.getGeofences(widget.userId).first;
      await _firebase.syncGeofencesToDevice(widget.deviceId, geofences);

      _cancelDrawing();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingGeofence != null
                ? 'Polygon updated successfully!'
                : 'Polygon created successfully!'),
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

  void _editGeofence(GeofenceModel geofence) {
    setState(() {
      _isDrawing = true;
      _editingGeofence = geofence;
      _vertices = List.from(geofence.vertices);
      _fenceName = geofence.name;
      _hasMovedToPolygon = false;
    });
  }

  void _showDeleteDialog(GeofenceModel geofence) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Polygon',
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
      await _firebase.updateGeofence(
          widget.userId, geofence.id, updated);
      final geofences =
          await _firebase.getGeofences(widget.userId).first;
      await _firebase.syncGeofencesToDevice(widget.deviceId, geofences);
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
      await _firebase.deleteGeofence(widget.userId, id);
      final geofences =
          await _firebase.getGeofences(widget.userId).first;
      await _firebase.syncGeofencesToDevice(widget.deviceId, geofences);
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
    final vertCount = geofence.vertices.length;

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
                child: Icon(Icons.polyline, size: 18, color: color),
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
                      '$vertCount-point polygon',
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
          // Vertices preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.vertical_split,
                    size: 13, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatVerticesPreview(geofence.vertices),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF6B7A99),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
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

  String _formatVerticesPreview(List<LatLng> vertices) {
    if (vertices.isEmpty) return 'No vertices';
    if (vertices.length <= 2) {
      return vertices
          .map((v) => '${v.latitude.toStringAsFixed(4)}, ${v.longitude.toStringAsFixed(4)}')
          .join('\n');
    }
    final first = vertices.first;
    return '${first.latitude.toStringAsFixed(4)}, ${first.longitude.toStringAsFixed(4)} ... +${vertices.length - 1} more';
  }
}

// ─── Device Location Marker ────────────────────────────────────────────────────

class _DeviceLocationMarker extends StatelessWidget {
  const _DeviceLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulse ring
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
        ),
        // Inner dot
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withOpacity(0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 14),
        ),
      ],
    );
  }
}
