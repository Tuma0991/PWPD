// lib/screens/map_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/device_data.dart';
import '../models/device_settings_model.dart';
import '../models/geofence_model.dart';
import '../models/paired_device.dart';
import '../services/firebase_service.dart';
import '../services/routing_service.dart';
import '../widgets/toast_notification.dart';

/// Combined live-location map and geofence manager.
///
/// View mode: live device position (with follow), geofence polygons overlaid,
/// and a bottom info card. Draw mode: place polygon vertices on the map.
/// The "Zones" action in the app bar opens the saved-zones list.
class MapScreen extends StatefulWidget {
  final String userId;
  final String deviceId;

  /// True while this tab is the visible one (offline toast only shows then).
  final bool isActive;

  /// Fired by HomeScreen on "View on Map" to recenter and draw the route.
  final ValueNotifier<int>? recenterRequest;

  /// All paired devices; non-active ones are shown as tappable pins.
  final List<PairedDevice> devices;

  /// Called when the user taps a non-active device pin to switch to it.
  final ValueChanged<String>? onSelectDevice;

  const MapScreen({
    super.key,
    required this.userId,
    required this.deviceId,
    this.isActive = true,
    this.recenterRequest,
    this.devices = const [],
    this.onSelectDevice,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with OfflineToastMixin {
  final FirebaseService _firebase = FirebaseService();
  final MapController _mapController = MapController();
  final RoutingService _routing = RoutingService();

  // ─── Live tracking ─────────────────────────────────────────────────────────
  LatLng? _deviceLocation;
  String _lastSeenLabel = 'Unknown';
  bool _isFollowing = true;
  bool _hasMovedOnce = false;
  DeviceData? _latestData;
  StreamSubscription<DeviceData>? _dataSub;
  final Map<String, LatLng> _secondaryLocations = {};
  final Map<String, StreamSubscription<DeviceData>> _secondarySubs = {};
  StreamSubscription<DeviceSettingsModel>? _settingsSub;
  String? _wearerPhotoBase64;
  String _deviceName = '';
  StreamSubscription<Map<String, dynamic>>? _emergencySub;
  bool _emergencyActive = false;
  String _emergencyReason = '';

  // ─── Guardian location + route ─────────────────────────────────────────────
  LatLng? _guardianLocation;
  StreamSubscription<Position>? _guardianSub;
  bool _routeProfileDriving = true;
  bool _satelliteView = true;
  List<LatLng>? _routePoints;
  bool _routeVisible = true;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  // ─── Drawing state ─────────────────────────────────────────────────────────
  bool _isDrawing = false;
  bool _hasMovedToPolygon = false;
  List<LatLng> _vertices = [];
  String _fenceName = '';
  GeofenceModel? _editingGeofence;

  // ─── Geofence violation handling ───────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _violationSub;
  final Set<String> _seenViolationKeys = {};
  final Map<String, bool> _deviceInsideGeofence = {};
  int _appStartThreshold = 0;

  static bool _isValidGps(double lat, double lng) =>
      lat.abs() > 0.5 || lng.abs() > 0.5;

  static const LatLng _defaultCenter = LatLng(10.0989, 122.8708);

  @override
  void initState() {
    super.initState();
    _subscribeToActiveDevice();
    _syncSecondarySubscriptions();
    widget.recenterRequest?.addListener(_recenter);
    _startGuardianTracking();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _subscribeToActiveDevice();
    }
    if (oldWidget.devices != widget.devices ||
        oldWidget.deviceId != widget.deviceId) {
      _syncSecondarySubscriptions();
    }
    if (oldWidget.recenterRequest != widget.recenterRequest) {
      oldWidget.recenterRequest?.removeListener(_recenter);
      widget.recenterRequest?.addListener(_recenter);
    }
  }

  /// (Re)subscribes to the active device's sensors, settings, violations and
  /// emergency streams. Called on init and whenever the active device changes.
  void _subscribeToActiveDevice() {
    _dataSub?.cancel();
    _violationSub?.cancel();
    _settingsSub?.cancel();
    _emergencySub?.cancel();

    _deviceLocation = null;
    _latestData = null;
    _lastSeenLabel = 'Unknown';
    _hasMovedOnce = false;
    _wearerPhotoBase64 = null;
    _deviceName = '';
    _emergencyActive = false;
    _emergencyReason = '';

    if (widget.deviceId.isEmpty) return;

    _dataSub = _firebase.listenToDeviceData(widget.deviceId).listen((data) {
      if (!mounted) return;
      setState(() {
        _latestData = data;
        _lastSeenLabel = data.lastSeenLabel;
        if (_isValidGps(data.latitude, data.longitude)) {
          final newLoc = LatLng(data.latitude, data.longitude);
          // Only update when it actually changed — avoids rebuilds that
          // reset the map view.
          if (_deviceLocation != newLoc) {
            _deviceLocation = newLoc;
            if (_isFollowing && !_isDrawing) {
              try {
                if (_hasMovedOnce) {
                  _mapController.move(newLoc, _mapController.camera.zoom);
                } else {
                  _mapController.move(newLoc, 15.0);
                  _hasMovedOnce = true;
                }
              } catch (_) {}
            }
          }
        }
      });
    });

    // Record app-open time so stale RTDB violations replayed by onChildAdded
    // are filtered out (30 s grace for clock skew).
    _appStartThreshold = DateTime.now().millisecondsSinceEpoch - 30000;

    _violationSub = _firebase
        .listenToGeofenceViolationsRTDB(widget.deviceId)
        .listen(_onViolation);

    _settingsSub = _firebase
        .listenToDeviceSettings(widget.deviceId)
        .listen((settings) {
      if (!mounted) return;
      setState(() {
        _wearerPhotoBase64 = settings.photoBase64;
        _deviceName = settings.name;
      });
    });

    _emergencySub = _firebase
        .listenToEmergencyAlert(widget.deviceId)
        .listen((data) {
      if (!mounted) return;
      setState(() {
        _emergencyActive = data['active'] == true;
        _emergencyReason = data['reason'] as String? ?? '';
      });
    });
  }

  /// Keeps a live location subscription for every paired device except the
  /// active one, so their pins move on the map without switching focus.
  void _syncSecondarySubscriptions() {
    final activeId = widget.deviceId;
    final wanted = widget.devices
        .map((d) => d.deviceId)
        .where((id) => id != activeId)
        .toSet();

    _secondarySubs.removeWhere((id, sub) {
      if (wanted.contains(id)) return false;
      sub.cancel();
      return true;
    });

    for (final id in wanted) {
      if (_secondarySubs.containsKey(id)) continue;
      _secondarySubs[id] = _firebase.listenToDeviceData(id).listen((data) {
        if (!mounted) return;
        if (!_isValidGps(data.latitude, data.longitude)) return;
        final loc = LatLng(data.latitude, data.longitude);
        if (_secondaryLocations[id] != loc) {
          setState(() => _secondaryLocations[id] = loc);
        }
      });
    }
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _violationSub?.cancel();
    _settingsSub?.cancel();
    _emergencySub?.cancel();
    _guardianSub?.cancel();
    _secondarySubs.forEach((_, sub) => sub.cancel());
    _secondarySubs.clear();
    widget.recenterRequest?.removeListener(_recenter);
    disposeOfflineToast();
    super.dispose();
  }

  Future<void> _startGuardianTracking() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      _guardianSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _guardianLocation = LatLng(pos.latitude, pos.longitude));
      });
    } catch (_) {}
  }

  Future<LatLng?> _getGuardianPositionOnce() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _recenter() async {
    final dest = _deviceLocation;
    if (dest == null) return;
    _isFollowing = true;

    var origin = _guardianLocation;
    origin ??= await _getGuardianPositionOnce();

    if (origin != null) {
      final route = await _routing.fetchRoute(
        origin,
        dest,
        profile: _routeProfileDriving ? 'driving' : 'foot',
      );
      if (!mounted) return;
      if (route != null) {
        setState(() {
          _routePoints = route.points;
          _routeVisible = true;
          _routeDistanceMeters = route.distanceMeters;
          _routeDurationSeconds = route.durationSeconds;
        });
        _fitRouteBounds(origin, dest, route.points);
        return;
      }
    }

    try {
      _mapController.move(dest, 15.0);
    } catch (_) {}
  }

  void _fitRouteBounds(LatLng origin, LatLng dest, List<LatLng> points) {
    final bounds = LatLngBounds.fromPoints([origin, dest, ...points]);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(70)),
      );
    } catch (_) {
      _mapController.move(dest, 15.0);
    }
  }

  Future<void> _onRouteProfileChanged(bool driving) async {
    setState(() => _routeProfileDriving = driving);
    final origin = _guardianLocation;
    final dest = _deviceLocation;
    if (origin == null || dest == null || _routePoints == null) return;
    final route = await _routing.fetchRoute(
      origin,
      dest,
      profile: driving ? 'driving' : 'foot',
    );
    if (!mounted || route == null) return;
    setState(() {
      _routePoints = route.points;
      _routeVisible = true;
      _routeDistanceMeters = route.distanceMeters;
      _routeDurationSeconds = route.durationSeconds;
    });
    _fitRouteBounds(origin, dest, route.points);
  }

  void _onMarkSafe() {
    _firebase.clearEmergency(widget.deviceId);
    setState(() => _routeVisible = false);
  }

  Future<void> _requestLocation() async {
    try {
      await _firebase.requestDeviceLocation(widget.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Location requested — the device will respond shortly.'),
          backgroundColor: const Color(0xFF1565C0),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not request location: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  String _formatRouteSummary() {
    final distance = _routeDistanceMeters;
    if (distance == null) return '';
    final km = distance / 1000.0;
    final distLabel = km < 1.0
        ? '${distance.round()} m'
        : '${km.toStringAsFixed(1)} km';
    final duration = _routeDurationSeconds;
    final min = duration == null ? null : (duration / 60.0).round();
    final timeLabel = min == null ? '' : ' · ~$min min';
    return 'Route: $distLabel$timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceId.isEmpty) return _buildNoDevice();
    if (widget.userId.isEmpty) return _buildLoginPrompt();

    final hasLocation = _deviceLocation != null;

    // _deviceLocation / _latestData are never cleared, so the map keeps the
    // last known position when the device goes offline.
    syncOfflineToast(
      offline: _latestData != null &&
          _latestData!.timestamp > 0 &&
          _latestData!.deviceOnline != true,
      active: widget.isActive && !_isDrawing,
      title: 'Device is offline',
      message: hasLocation
          ? 'Showing the last known location — it may not be current.'
          : 'No location has been saved from the device yet.',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: _isDrawing ? _buildDrawAppBar() : _buildViewAppBar(),
      body: StreamBuilder<List<GeofenceModel>>(
        stream: _firebase.getGeofences(widget.userId),
        builder: (context, snapshot) {
          final geofences = snapshot.data ?? [];

          if (_isDrawing) {
            if (_vertices.isNotEmpty && !_hasMovedToPolygon) {
              _hasMovedToPolygon = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fitMapToVertices();
              });
            }
            return _buildDrawBody();
          }

          return _buildViewBody(geofences, hasLocation);
        },
      ),
      floatingActionButton: null,
    );
  }

  // ─── App bars ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildViewAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1565C0),
      elevation: 0,
      title: const Row(
        children: [
          Icon(Icons.map, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Live Location',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      actions: [
        // Locate now — ask the device to turn GPS on and report immediately
        IconButton(
          onPressed: _requestLocation,
          icon: const Icon(Icons.location_searching, color: Colors.white, size: 20),
          tooltip: 'Locate now',
        ),
        // Saved zones
        IconButton(
          onPressed: _openZonesSheet,
          icon: const Icon(Icons.add_location_alt, color: Colors.white, size: 20),
          tooltip: 'Zones',
        ),
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
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
    );
  }

  PreferredSizeWidget _buildDrawAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1565C0),
      elevation: 0,
      title: Row(
        children: [
          const Icon(Icons.edit_location_alt, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            _editingGeofence != null ? 'Edit Polygon' : 'Draw Polygon',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _cancelDrawing,
      ),
    );
  }

  // ─── View mode ─────────────────────────────────────────────────────────────

  Widget _buildViewBody(List<GeofenceModel> geofences, bool hasLocation) {
    final center = _deviceLocation ?? _defaultCenter;

    return Stack(
      children: [
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
            TileLayer(
              urlTemplate: _satelliteView
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pwpd.application',
              maxZoom: 19,
              additionalOptions: const {
                'User-Agent': 'pwpd/1.0 (Flutter; Android)',
              },
            ),

            // Saved geofence polygons
            PolygonLayer(
              polygons: [
                for (final gf in geofences)
                  if (gf.vertices.length >= 3)
                    Polygon(
                      points: [...gf.vertices, gf.vertices.first],
                      color: _polygonFillColor(gf),
                      borderColor: _polygonBorderColor(gf),
                      borderStrokeWidth: gf.enabled ? 2.5 : 1.0,
                    ),
              ],
            ),

            // Road-following route from guardian to device
            if (_routePoints != null && _routeVisible)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints!,
                    strokeWidth: 5,
                    color: const Color(0xFF2E7D32),
                  ),
                ],
              ),

            MarkerLayer(
              markers: [
                for (final d in widget.devices)
                  if (d.deviceId != widget.deviceId &&
                      _secondaryLocations[d.deviceId] != null)
                    Marker(
                      point: _secondaryLocations[d.deviceId]!,
                      width: 140,
                      height: 56,
                      child: _SecondaryDeviceMarker(
                        name: d.displayName,
                        onTap: widget.onSelectDevice == null
                            ? null
                            : () => widget.onSelectDevice!(d.deviceId),
                      ),
                    ),
                if (hasLocation)
                  Marker(
                    point: _deviceLocation!,
                    width: 48,
                    height: 48,
                    child: _DeviceMarker(photoBase64: _wearerPhotoBase64),
                  ),
                if (_guardianLocation != null)
                  Marker(
                    point: _guardianLocation!,
                    width: 40,
                    height: 48, // was 40 — caused "BOTTOM OVERFLOWED BY 1.00 PIXELS"
                    child: const _GuardianMarker(),
                  ),
              ],
            ),
          ],
        ),

        // Floating drive/walk toggle + route line on/off (top-left of map)
        Positioned(
          top: 12,
          left: 16,
          child: Row(
            children: [
              _RouteProfileToggle(
                driving: _routeProfileDriving,
                onChanged: _onRouteProfileChanged,
              ),
              const SizedBox(width: 8),
              _RouteToggleButton(
                visible: _routePoints != null && _routeVisible,
                onPressed: () {
                  if (_routePoints == null) {
                    // No route yet (fresh open) — fetch one.
                    _recenter();
                  } else {
                    setState(() => _routeVisible = !_routeVisible);
                  }
                },
              ),
            ],
          ),
        ),

        // Map type toggle (satellite / standard) — top-right of map
        Positioned(
          top: 12,
          right: 16,
          child: _MapTypeToggle(
            satellite: _satelliteView,
            onChanged: (v) => setState(() => _satelliteView = v),
          ),
        ),

        // Emergency "Mark as safe" banner
        if (_emergencyActive)
          Positioned(
            top: 64,
            left: 16,
            right: 16,
            child: _EmergencyBanner(
              reason: _emergencyReason,
              onMarkSafe: _onMarkSafe,
            ),
          ),

        // Bottom info card
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: _buildInfoCard(hasLocation),
        ),

        // No-location overlay
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
                        color: Colors.white.withValues(alpha: 0.85),
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
                        color: Colors.white.withValues(alpha: 0.85),
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
    );
  }

  Widget _buildInfoCard(bool hasLocation) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.12),
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
              color: const Color(0xFF1565C0).withValues(alpha: 0.10),
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
                Text(
                  _deviceName.trim().isEmpty
                      ? 'Device Location'
                      : "${_deviceName.trim()}'s Location",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
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
                if (_routeDistanceMeters != null &&
                    _routePoints != null &&
                    _routeVisible) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatRouteSummary(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hasLocation
                  ? (_latestData?.deviceOnline == true
                      ? const Color(0xFF43A047).withValues(alpha: 0.10)
                      : const Color(0xFFE53935).withValues(alpha: 0.08))
                  : const Color(0xFF9EA8C2).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasLocation
                    ? (_latestData?.deviceOnline == true
                        ? const Color(0xFF43A047).withValues(alpha: 0.3)
                        : const Color(0xFFE53935).withValues(alpha: 0.3))
                    : const Color(0xFF9EA8C2).withValues(alpha: 0.3),
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
    );
  }

  // ─── Draw mode ─────────────────────────────────────────────────────────────

  Widget _buildDrawBody() {
    return Column(
      children: [
        _buildDrawingHint(),
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 15,
              onTap: (tapPosition, point) {
                setState(() => _vertices.add(point));
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _satelliteView
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pwpd.application',
                additionalOptions: const {
                  'User-Agent': 'pwpd/1.0 (Flutter; Android)',
                },
              ),

              // Placed vertices
              if (_vertices.isNotEmpty)
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
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
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

              // Polygon fill (3+ vertices)
              if (_vertices.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: [..._vertices, _vertices.first],
                      color: const Color(0xFF1565C0).withValues(alpha: 0.10),
                      borderColor: const Color(0xFF1565C0),
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),

              // Connecting lines
              if (_vertices.length >= 2)
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
        Expanded(flex: 1, child: _buildDrawingPanel()),
      ],
    );
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

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.10),
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
                          color: const Color(0xFF1565C0).withValues(alpha: 0.2),
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

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _vertices.isEmpty ? null : _undoLastVertex,
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _vertices.isEmpty ? null : _clearAllVertices,
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

  // ─── Zones sheet ───────────────────────────────────────────────────────────

  void _openZonesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildZonesSheet(),
    );
  }

  Widget _buildZonesSheet() {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (sheetContext, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE3F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    const Text(
                      'Saved Zones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2340),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _startDrawing();
                      },
                      icon: const Icon(Icons.add,
                          size: 18, color: Color(0xFF1565C0)),
                      label: const Text(
                        'New',
                        style: TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<GeofenceModel>>(
                  stream: _firebase.getGeofences(widget.userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF1565C0)));
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Error loading zones',
                            style: TextStyle(color: Color(0xFF6B7A99)),
                          ),
                        ),
                      );
                    }

                    final geofences = snapshot.data ?? [];
                    if (geofences.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
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
                              'Tap "New" to draw a custom zone',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7A99)),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: geofences.length,
                      itemBuilder: (context, index) {
                        final geofence = geofences[index];
                        return _GeofenceCard(
                          geofence: geofence,
                          isDeviceInside: _deviceInsideGeofence[geofence.id],
                          onEdit: () {
                            Navigator.pop(sheetContext);
                            _editGeofence(geofence);
                          },
                          onDelete: () => _showDeleteDialog(geofence),
                          onToggle: () => _toggleGeofence(geofence),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Drawing helpers ───────────────────────────────────────────────────────

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

  // ─── Geofence violation handler ────────────────────────────────────────────

  void _onViolation(Map<String, dynamic> data) {
    final key = data['_rtdbKey'] as String?;
    if (key == null) return;

    final isNew = _seenViolationKeys.add(key);
    if (!isNew) return;

    final violationTs = data['timestamp'] as int?;
    if (violationTs != null && violationTs < _appStartThreshold) return;

    final type = data['type'] as String? ?? '';
    final name = data['name'] as String? ?? 'Unknown zone';
    final geofenceId = data['geofenceId'] as String? ?? '';

    if (geofenceId.isNotEmpty) {
      setState(() {
        _deviceInsideGeofence[geofenceId] = type == 'entered';
      });
    }

    if (mounted) {
      final isExit = type == 'exited';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isExit ? Icons.location_off : Icons.location_on,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isExit
                      ? 'Device left "$name"'
                      : 'Device entered "$name"',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: isExit
              ? const Color(0xFFE53935)
              : const Color(0xFF2E7D32),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    // Bridge RTDB violation → Firestore so it appears in AlertsScreen
    final userId = widget.userId;
    if (userId.isNotEmpty) {
      _firebase.logGeofenceViolationToAlerts(userId, {
        ...data,
        'deviceId': widget.deviceId,
      });
      _firebase.logGeofenceViolation(userId, {
        ...data,
        'deviceId': widget.deviceId,
      });
    }
  }

  Color _polygonFillColor(GeofenceModel gf) {
    if (!gf.enabled) return Colors.grey.withValues(alpha: 0.05);
    final status = _deviceInsideGeofence[gf.id];
    if (status == true) {
      return const Color(0xFF4CAF50).withValues(alpha: 0.12);
    }
    if (status == false) {
      return const Color(0xFFE53935).withValues(alpha: 0.12);
    }
    return const Color(0xFF1565C0).withValues(alpha: 0.1);
  }

  Color _polygonBorderColor(GeofenceModel gf) {
    if (!gf.enabled) return Colors.grey;
    final status = _deviceInsideGeofence[gf.id];
    if (status == true) return const Color(0xFF4CAF50);
    if (status == false) return const Color(0xFFE53935);
    return const Color(0xFF1565C0);
  }

  // ─── Save / Edit / Delete / Toggle ─────────────────────────────────────────

  Future<void> _savePolygon() async {
    if (_vertices.length < 3 || _fenceName.isEmpty) return;

    try {
      if (_editingGeofence != null) {
        final updated = _editingGeofence!.copyWith(
          name: _fenceName,
          vertices: List.from(_vertices),
          updatedAt: DateTime.now(),
        );
        await _firebase.updateGeofence(
            widget.userId, _editingGeofence!.id, updated);
      } else {
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

      final geofences = await _firebase.getGeofences(widget.userId).first;
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
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Polygon',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Delete "${geofence.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _deleteGeofence(geofence.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
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
      await _firebase.updateGeofence(widget.userId, geofence.id, updated);
      final geofences = await _firebase.getGeofences(widget.userId).first;
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
      final geofences = await _firebase.getGeofences(widget.userId).first;
      await _firebase.syncGeofencesToDevice(widget.deviceId, geofences);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // ─── Guard screens ─────────────────────────────────────────────────────────

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

  Widget _buildLoginPrompt() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text('Live Location',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: const Center(
        child: Text(
          'Please log in to use the map and geofences',
          style: TextStyle(color: Color(0xFF6B7A99)),
        ),
      ),
    );
  }
}

// ─── Secondary device pin (tap to switch) ───────────────────────────────────

class _SecondaryDeviceMarker extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _SecondaryDeviceMarker({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6B7A99), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.location_on,
                color: Color(0xFF1565C0), size: 16),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2340),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Device marker widget ─────────────────────────────────────────────────────

class _DeviceMarker extends StatelessWidget {
  final String? photoBase64;

  const _DeviceMarker({this.photoBase64});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoBase64 != null && photoBase64!.isNotEmpty;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
        ),
        if (hasPhoto)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.memory(
                base64Decode(photoBase64!),
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.person,
                  color: Color(0xFF1565C0),
                  size: 18,
                ),
              ),
            ),
          )
        else
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.4),
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

// ─── Guardian marker widget ────────────────────────────────────────────────────

class _GuardianMarker extends StatelessWidget {
  const _GuardianMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.my_location, color: Colors.white, size: 14),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'You',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Route profile toggle widget ───────────────────────────────────────────────

class _RouteProfileToggle extends StatelessWidget {
  final bool driving;
  final ValueChanged<bool> onChanged;

  const _RouteProfileToggle({required this.driving, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.directions_car,
            selected: driving,
            onTap: () => onChanged(true),
          ),
          _segment(
            icon: Icons.directions_walk,
            selected: !driving,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? Colors.white : const Color(0xFF6B7A99),
        ),
      ),
    );
  }
}

// ─── Map type toggle widget ─────────────────────────────────────────────────

class _MapTypeToggle extends StatelessWidget {
  final bool satellite;
  final ValueChanged<bool> onChanged;

  const _MapTypeToggle({required this.satellite, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.satellite_alt,
            selected: satellite,
            onTap: () => onChanged(true),
          ),
          _segment(
            icon: Icons.map,
            selected: !satellite,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? Colors.white : const Color(0xFF6B7A99),
        ),
      ),
    );
  }
}

// ─── Route visibility toggle button ───────────────────────────────────────────

class _RouteToggleButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onPressed;

  const _RouteToggleButton({required this.visible, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: visible ? const Color(0xFF2E7D32) : Colors.white,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.alt_route,
            size: 20,
            color: visible ? Colors.white : const Color(0xFF2E7D32),
          ),
        ),
      ),
    );
  }
}

// ─── Emergency banner widget ──────────────────────────────────────────────────

class _EmergencyBanner extends StatelessWidget {
  final String reason;
  final VoidCallback onMarkSafe;

  const _EmergencyBanner({required this.reason, required this.onMarkSafe});

  @override
  Widget build(BuildContext context) {
    final isSos = reason.contains('SOS button');
    final isFall = reason.contains('Fall');
    final title = isSos
        ? 'SOS ALERT!'
        : isFall
            ? 'FALL DETECTED'
            : 'EMERGENCY ALERT!';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSos ? Icons.emergency : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ),
          TextButton(
            onPressed: onMarkSafe,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text(
              'Mark as Safe',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Geofence card widget ─────────────────────────────────────────────────────

class _GeofenceCard extends StatelessWidget {
  final GeofenceModel geofence;
  final bool? isDeviceInside;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _GeofenceCard({
    required this.geofence,
    required this.isDeviceInside,
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
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
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
                  color: color.withValues(alpha: 0.10),
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
                            : Colors.grey.withValues(alpha: 0.6),
                      ),
                    ),
                    if (geofence.enabled && isDeviceInside != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isDeviceInside!
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isDeviceInside! ? 'Device inside' : 'Device outside',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDeviceInside!
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFE53935),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: geofence.enabled,
                onChanged: (_) => onToggle(),
                activeThumbColor: const Color(0xFF1565C0),
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