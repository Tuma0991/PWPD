// lib/screens/alerts_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../models/device_settings_model.dart';
import '../services/firebase_service.dart';

/// Which alerts the history list is currently showing.
enum _AlertFilter { all, fall, sos, geo }

class AlertsScreen extends StatefulWidget {
  final String deviceId;
  const AlertsScreen({super.key, required this.deviceId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final FirebaseService _firebase = FirebaseService();
  StreamSubscription<Map<String, dynamic>>? _emergencySubscription;
  bool _previousEmergencyActive = false;
  String _previousEmergencyReason = '';
  bool _isFirstEvent = true;

  DateTime? _lastSOSTime;
  int? _lastLoggedTriggeredAt;
  static const _sosFallSuppressSeconds = 3;

  _AlertFilter _filter = _AlertFilter.all;

  /// Name the guardian assigned to the wearer (from device settings).
  StreamSubscription<DeviceSettingsModel>? _settingsSub;
  String _wearerName = '';

  @override
  void initState() {
    super.initState();
    _subscribeToEmergencyEvents();
    if (widget.deviceId.isNotEmpty) {
      _settingsSub =
          _firebase.listenToDeviceSettings(widget.deviceId).listen((settings) {
        if (!mounted) return;
        setState(() => _wearerName = settings.name.trim());
      });
    }
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  /// Same grouping the list badges use: fall, geofence, or everything else
  /// (SOS button and generic emergencies) as "SOS".
  _AlertFilter _categoryOf(Map<String, dynamic> alert) {
    final type = (alert['type'] ?? 'unknown').toString();
    if (type == 'fall') return _AlertFilter.fall;
    if (type.startsWith('geofence_')) return _AlertFilter.geo;
    return _AlertFilter.sos;
  }

  void _toggleFilter(_AlertFilter f) {
    setState(() => _filter = _filter == f ? _AlertFilter.all : f);
  }

  String _filterName(_AlertFilter f) {
    switch (f) {
      case _AlertFilter.fall:
        return 'fall';
      case _AlertFilter.sos:
        return 'SOS';
      case _AlertFilter.geo:
        return 'geofence';
      case _AlertFilter.all:
        return '';
    }
  }

  void _subscribeToEmergencyEvents() {
    _emergencySubscription =
        _firebase.listenToEmergencyAlert(widget.deviceId).listen((event) async {
      // Skip initial snapshot — it's existing RTDB state, not a new event.
      // Otherwise any stale active emergency is re-logged on every app start.
      if (_isFirstEvent) {
        _isFirstEvent = false;
        _previousEmergencyActive = event['active'] == true;
        _previousEmergencyReason = event['reason'] as String? ?? '';
        return;
      }

      final isEmergencyActive = event['active'] == true;
      final emergencyReason = event['reason'] as String? ?? '';
      final userId = _firebase.currentUser?.uid;
      final triggeredAt = event['triggeredAt'] as int?;

      if (!mounted) return;

      // Capture previous state before updating, so dismiss transitions
      // (active→inactive) reset the previous-active flag. Without this,
      // dismissing and re-triggering SOS was seen as a duplicate because
      // the inactive event returned early without updating the flag.
      final wasPreviouslyActive = _previousEmergencyActive;
      final wasPreviouslyReason = _previousEmergencyReason;
      _previousEmergencyActive = isEmergencyActive;
      _previousEmergencyReason = emergencyReason;

      // ESP32 writes emergency fields individually (active, reason,
      // triggeredAt, lat, lng as separate RTDB calls). Each write fires
      // onValue. Skip incomplete events that don't have a reason yet —
      // otherwise the first event ({active:true, reason:""}) logs a bogus
      // "emergency" alert with no message.
      if (!isEmergencyActive || emergencyReason.isEmpty) return;

      final isNewEmergency =
          !wasPreviouslyActive ||
              emergencyReason != wasPreviouslyReason;

      if (!isNewEmergency || userId == null || userId.isEmpty) return;

      // Prevent duplicate: same triggeredAt timestamp was already logged
      if (triggeredAt != null && triggeredAt == _lastLoggedTriggeredAt) return;
      _lastLoggedTriggeredAt = triggeredAt;

      final isSOSButton = emergencyReason.contains('SOS button');
      final isFall = emergencyReason.contains('Fall detected') ||
          emergencyReason.contains('accelerometer');

      if (isSOSButton) {
        _lastSOSTime = DateTime.now();
      }

      if (isFall && _lastSOSTime != null) {
        final secondsSinceSOS =
            DateTime.now().difference(_lastSOSTime!).inSeconds;
        if (secondsSinceSOS < _sosFallSuppressSeconds) {
          debugPrint(
              '[AlertsScreen] Suppressed false fall alert caused by SOS button jolt.');
          return;
        }
      }

      final alertType = isSOSButton ? 'sos' : (isFall ? 'fall' : 'emergency');

      final alertData = <String, dynamic>{
        'type': alertType,
        'message': isSOSButton
            ? 'Emergency SOS button pressed'
            : isFall
                ? 'Fall detected on device'
                : emergencyReason,
        'deviceId': widget.deviceId,
        'reason': emergencyReason,
      };

      // Use ESP32's triggeredAt so alert time reflects when the emergency
      // actually occurred, not when the app processed it.
      if (triggeredAt != null && triggeredAt > 0) {
        alertData['timestamp'] =
            Timestamp.fromMillisecondsSinceEpoch(triggeredAt);
      }

      // Include GPS coordinates if available
      if (event['lat'] != null) {
        alertData['latitude'] = event['lat'];
        alertData['longitude'] = event['lng'];
      }

      await _firebase.logAlert(userId, alertData);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceId.isEmpty) return _buildNoDevice();

    final userId = _firebase.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Alert History',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: userId.isEmpty
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _firebase.getAlertHistory(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final alerts = snapshot.data ?? [];

                if (alerts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_none,
                            size: 56,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No alerts yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2340),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Emergency events from your device\nwill appear here.',
                          style: TextStyle(
                              color: Color(0xFF6B7A99), fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final fallCount = alerts
                    .where((a) => _categoryOf(a) == _AlertFilter.fall)
                    .length;
                final sosCount = alerts
                    .where((a) => _categoryOf(a) == _AlertFilter.sos)
                    .length;
                final geoCount = alerts
                    .where((a) => _categoryOf(a) == _AlertFilter.geo)
                    .length;

                final visible = _filter == _AlertFilter.all
                    ? alerts
                    : alerts.where((a) => _categoryOf(a) == _filter).toList();

                return Column(
                  children: [
                    // Summary bar — each chip filters the list below
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      color: const Color(0xFF1565C0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _AlertSummaryChip(
                              label: '$fallCount Falls',
                              color: const Color(0xFFEF5350),
                              icon: Icons.personal_injury,
                              selected: _filter == _AlertFilter.fall,
                              onTap: () => _toggleFilter(_AlertFilter.fall),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AlertSummaryChip(
                              label: '$sosCount SOS',
                              color: const Color(0xFFFFA726),
                              icon: Icons.warning_amber,
                              selected: _filter == _AlertFilter.sos,
                              onTap: () => _toggleFilter(_AlertFilter.sos),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AlertSummaryChip(
                              label: '$geoCount Geo',
                              color: const Color(0xFF7C4DFF),
                              icon: Icons.location_off,
                              selected: _filter == _AlertFilter.geo,
                              onTap: () => _toggleFilter(_AlertFilter.geo),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _AlertSummaryChip(
                              label: '${alerts.length} Total',
                              color: Colors.white,
                              icon: Icons.list_alt,
                              selected: _filter == _AlertFilter.all,
                              onTap: () => setState(
                                  () => _filter = _AlertFilter.all),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: visible.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.filter_list_off,
                                        size: 40, color: Color(0xFF9EA8C2)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No ${_filterName(_filter)} alerts',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6B7A99),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Tap Total to see all alerts',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9EA8C2),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(overscroll: false),
                                child: ListView.separated(
                                  physics: const ClampingScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 20, 16, 32),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final alert = visible[i];
                                    final type = alert['type'] ?? 'unknown';
                                    final message = alert['message'] ?? 'Alert';
                                    final ts = alert['timestamp'];
                                    final isFall = type == 'fall';
                                    final isGeofence =
                                        type.startsWith('geofence_');
                                    final isGeofenceExit =
                                        type == 'geofence_exited';
                                    final color = isFall || isGeofenceExit
                                        ? const Color(0xFFE53935)
                                        : isGeofence
                                            ? const Color(0xFF7C4DFF)
                                            : const Color(0xFFF57C00);

                                    String timeStr = 'Unknown time';
                                    if (ts != null) {
                                      try {
                                        final dt = (ts as dynamic).toDate();
                                        timeStr = DateFormat('MMM d, y · h:mm a')
                                            .format(dt);
                                      } catch (_) {}
                                    }

                                    return GestureDetector(
                                      onTap: () =>
                                          _showAlertDetails(context, alert),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        padding: const EdgeInsets.all(15),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: color.withValues(alpha: 0.15),
                                              width: 1.5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: color.withValues(alpha: 0.06),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(11),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                isFall
                                                    ? Icons.personal_injury
                                                    : isGeofence
                                                        ? Icons.location_off
                                                        : Icons.warning_amber,
                                                color: color,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 3),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: color
                                                              .withValues(alpha: 0.10),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          isFall
                                                              ? 'FALL'
                                                              : isGeofence
                                                                  ? 'GEO'
                                                                  : 'SOS',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: color,
                                                            fontSize: 11,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    message,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF1A2340),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                          Icons.access_time,
                                                          size: 12,
                                                          color: Color(
                                                              0xFF9EA8C2)),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        timeStr,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Color(0xFF9EA8C2),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(Icons.chevron_right,
                                                color: color.withValues(alpha: 0.4),
                                                size: 18),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  void _showAlertDetails(BuildContext context, Map<String, dynamic> alert) {
    final type = (alert['type'] ?? 'unknown').toString();
    final message = (alert['message'] ?? 'Alert').toString();
    final reason = alert['reason']?.toString();
    final deviceId = alert['deviceId']?.toString();
    final lat = alert['latitude'];
    final lng = alert['longitude'];
    final ts = alert['timestamp'];

    final isFall = type == 'fall';
    final isGeofence = type.startsWith('geofence_');
    final isGeofenceExit = type == 'geofence_exited';
    final color = isFall || isGeofenceExit
        ? const Color(0xFFE53935)
        : isGeofence
            ? const Color(0xFF7C4DFF)
            : const Color(0xFFF57C00);
    final icon = isFall
        ? Icons.personal_injury
        : isGeofence
            ? Icons.location_off
            : Icons.warning_amber;
    final typeLabel = isFall
        ? 'Fall Detected'
        : isGeofence
            ? (isGeofenceExit ? 'Geofence Exited' : 'Geofence Entered')
            : (type == 'sos' ? 'SOS Alert' : 'Emergency Alert');

    String timeStr = 'Unknown time';
    if (ts != null) {
      try {
        final dt = (ts as dynamic).toDate();
        timeStr = DateFormat('MMMM d, y · h:mm a').format(dt);
      } catch (_) {}
    }

    LatLng? location;
    if (lat is num && lng is num && (lat != 0 || lng != 0)) {
      location = LatLng(lat.toDouble(), lng.toDouble());
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final loc = location;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9DFEB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: color, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              typeLabel,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A2340),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9EA8C2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Color(0xFF9EA8C2)),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (loc != null) ...[
                    _AlertLocationMap(location: loc),
                    const SizedBox(height: 20),
                  ],
                  _detailRow(Icons.subject, 'Message', message),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _detailRow(Icons.info_outline, 'Reason', reason),
                  ],
                  if (deviceId != null && deviceId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _detailRow(
                      Icons.devices,
                      'Device',
                      // Use the wearer's name for the current device; fall
                      // back to the ID for older alerts or if no name is set.
                      (deviceId == widget.deviceId && _wearerName.isNotEmpty)
                          ? _wearerName
                          : deviceId,
                    ),
                  ],
                  if (loc != null) ...[
                    const SizedBox(height: 12),
                    _detailRow(
                      Icons.location_on,
                      'Location',
                      '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1565C0)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9EA8C2),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2340),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
            Icon(Icons.notifications_active, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Alert History',
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

class _AlertLocationMap extends StatelessWidget {
  final LatLng location;
  const _AlertLocationMap({required this.location});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: location,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pwpd.application',
              maxZoom: 19,
              additionalOptions: const {
                'User-Agent': 'pwpd/1.0 (Flutter; Android)',
              },
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: location,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_pin,
                    color: Color(0xFFE53935),
                    size: 40,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertSummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AlertSummaryChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.40 : 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.white : color.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}