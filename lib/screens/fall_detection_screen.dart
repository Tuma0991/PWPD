// lib/screens/fall_detection_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/language_service.dart';
import '../models/device_data.dart';
import '../widgets/toast_notification.dart';

/// Wearer status the hero shows.
///
/// Movement levels (still → vigorous) are computed in the app from the raw
/// accelerometer, NOT taken from the device's `mode` field, so a wearable that
/// is lying on a table reads as "still" instead of "active".
enum _Status { sos, fall, still, light, moving, vigorous, waiting, offline }

/// Movement view for caregivers (mostly parents/guardians).
///
/// The hero shows the wearer's current status in plain language; the raw
/// accelerometer axes are tucked behind a collapsible "Sensor readings" panel.
/// Emergencies are cleared from the Map tab ("Mark as Safe"), not here.
class FallDetectionScreen extends StatefulWidget {
  final String deviceId;

  /// True while this tab is the visible one (offline toast only shows then).
  final bool isActive;
  const FallDetectionScreen(
      {super.key, required this.deviceId, this.isActive = true});

  @override
  State<FallDetectionScreen> createState() => _FallDetectionScreenState();
}

class _FallDetectionScreenState extends State<FallDetectionScreen>
    with OfflineToastMixin {
  String get deviceId => widget.deviceId;

  // ─── Movement tuning ──────────────────────────────────────────────────────
  // Movement = how far the acceleration magnitude is from 1 g (gravity),
  // averaged over the last few samples. Adjust these if the levels feel off.
  static const int _windowSize = 8;
  static const double _stillMax = 0.08;
  static const double _lightMax = 0.25;
  static const double _movingMax = 0.60;

  /// Last data the device sent — kept as a baseline if it drops offline.
  DeviceData? _lastData;

  /// Recent movement samples (deviation from 1 g), newest last.
  final List<double> _recentDeviation = [];
  num _lastSampleTs = -1;

  /// When the wearer first appeared still (while this screen has been alive).
  DateTime? _stillSince;

  @override
  void dispose() {
    disposeOfflineToast();
    super.dispose();
  }

  String _t(bool isTagalog, String en, String fil) => isTagalog ? fil : en;

  /// Deviation from 1 g, or null if the reading is unusable (all zeros).
  double? _deviationG(DeviceData d) {
    var mag = math.sqrt(
        d.accelX * d.accelX + d.accelY * d.accelY + d.accelZ * d.accelZ);
    if (mag < 0.1) return null; // no real sensor reading
    if (mag > 4) mag /= 9.80665; // values look like m/s², convert to g
    return (mag - 1.0).abs();
  }

  void _ingest(DeviceData d) {
    if (d.timestamp == _lastSampleTs) return; // same sample, already counted
    _lastSampleTs = d.timestamp;
    final dev = _deviationG(d);
    if (dev == null) return;
    _recentDeviation.add(dev);
    if (_recentDeviation.length > _windowSize) _recentDeviation.removeAt(0);
  }

  _Status _movementLevel() {
    if (_recentDeviation.isEmpty) return _Status.waiting;
    final avg =
        _recentDeviation.reduce((a, b) => a + b) / _recentDeviation.length;
    if (avg < _stillMax) return _Status.still;
    if (avg < _lightMax) return _Status.light;
    if (avg < _movingMax) return _Status.moving;
    return _Status.vigorous;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LanguageService.isTagalog,
      builder: (context, isTagalog, _) {
        if (deviceId.isEmpty) return _buildNoDevice(context, isTagalog);
        final firebase = FirebaseService();

        return Scaffold(
          backgroundColor: const Color(0xFFF0F4FF),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1565C0),
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.sensors, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  _t(isTagalog, 'Movement', 'Paggalaw'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white),
                tooltip: _t(isTagalog, 'How Fall Detection Works',
                    'Paano Gumagana ang Fall Detection'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    insetPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 24),
                    child: SingleChildScrollView(
                      child: _buildHowItWorks(
                        isTagalog,
                        onClose: () => Navigator.pop(dialogContext),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: StreamBuilder<Map<String, dynamic>>(
            stream: firebase.listenToEmergencyAlert(deviceId),
            builder: (context, emergencySnapshot) {
              final emergencyData = emergencySnapshot.data ?? {};
              final isEmergencyActive = emergencyData['active'] == true;
              final emergencyReason = emergencyData['reason'] as String? ?? '';
              final isSOSButton = emergencyReason.contains('SOS button');
              final isFallDetection = emergencyReason.contains('Fall detected');

              return StreamBuilder<DeviceData>(
                stream: firebase.listenToDeviceData(deviceId),
                builder: (context, snapshot) {
                  if (snapshot.hasData) _lastData = snapshot.data;
                  final data = snapshot.data ?? _lastData;
                  if (data != null) _ingest(data);

                  final isFall = isEmergencyActive &&
                      (isSOSButton ||
                          isFallDetection ||
                          (data?.fallDetected ?? false));
                  final hasData = data != null && data.timestamp > 0;
                  final isOnline = data?.deviceOnline ?? false;
                  final status = _classifyStatus(
                    isFall: isFall,
                    isSOS: isSOSButton,
                    hasData: hasData,
                    isOnline: isOnline,
                  );

                  // Track how long the wearer has been still.
                  if (status == _Status.still) {
                    _stillSince ??= DateTime.now();
                  } else {
                    _stillSince = null;
                  }

                  syncOfflineToast(
                    offline: status == _Status.offline,
                    active: widget.isActive,
                    title: _t(isTagalog, 'This data is not live',
                        'Hindi live ang data na ito'),
                    message: _t(
                        isTagalog,
                        'The device is offline, so the information below is from the last data saved by the app.',
                        'Offline ang device, kaya ang impormasyon sa ibaba ay mula sa huling na-save na data ng app.'),
                  );

                  return ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(overscroll: false),
                    child: ListView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(0),
                      children: [
                        _buildHero(isTagalog, status),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatusCard(isTagalog, data, status),
                              const SizedBox(height: 16),
                              _buildSensorDetails(
                                  context, isTagalog, data, isOnline),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // ─── Status classification ────────────────────────────────────────────────

  _Status _classifyStatus({
    required bool isFall,
    required bool isSOS,
    required bool hasData,
    required bool isOnline,
  }) {
    // A live emergency always wins, even if the device has since gone quiet.
    if (isFall) return isSOS ? _Status.sos : _Status.fall;
    // No heartbeat yet — nothing meaningful to show.
    if (!hasData) return _Status.waiting;
    // Heartbeat is stale — the data on screen is the last saved snapshot.
    if (!isOnline) return _Status.offline;
    // Otherwise: movement level computed from the accelerometer.
    return _movementLevel();
  }

  // ─── Hero (dynamic status) ────────────────────────────────────────────────

  Widget _buildHero(bool isTagalog, _Status status) {
    final String title;
    final String subtitle;
    final IconData icon;
    final List<Color> gradient;

    switch (status) {
      case _Status.sos:
        title = _t(isTagalog, 'SOS ALERT!', 'SOS!');
        subtitle = _t(isTagalog, 'Emergency button was pressed on the device!',
            'Pinindot ang emergency button sa device!');
        icon = Icons.emergency;
        gradient = const [
          Color(0xFFB71C1C),
          Color(0xFFE53935),
          Color(0xFFEF5350),
        ];
      case _Status.fall:
        title = _t(isTagalog, 'FALL DETECTED!', 'NAHULOG!');
        subtitle = _t(isTagalog, 'A possible fall was detected.',
            'May nakitang posibleng pagbagsak.');
        icon = Icons.personal_injury;
        gradient = const [
          Color(0xFFB71C1C),
          Color(0xFFE53935),
          Color(0xFFEF5350),
        ];
      case _Status.still:
        title = _t(isTagalog, 'Staying Still', 'Nakatigil');
        subtitle = _t(isTagalog, 'No movement detected right now.',
            'Walang nakikitang paggalaw ngayon.');
        icon = Icons.self_improvement;
        gradient = const [
          Color(0xFF00695C),
          Color(0xFF00897B),
          Color(0xFF26A69A),
        ];
      case _Status.light:
        title = _t(isTagalog, 'Light Movement', 'Bahagyang Gumagalaw');
        subtitle = _t(isTagalog, 'Small movements detected.',
            'May maliliit na paggalaw na nakita.');
        icon = Icons.accessibility_new;
        gradient = const [
          Color(0xFF1565C0),
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
        ];
      case _Status.moving:
        title = _t(isTagalog, 'Moving', 'Gumagalaw');
        subtitle = _t(isTagalog, 'Your loved one is moving around.',
            'Gumagalaw ang iyong mahal sa buhay.');
        icon = Icons.directions_walk;
        gradient = const [
          Color(0xFF1565C0),
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
        ];
      case _Status.vigorous:
        title = _t(isTagalog, 'Very Active', 'Napakaaktibo');
        subtitle = _t(isTagalog, 'Lots of movement detected.',
            'Maraming paggalaw ang nakita.');
        icon = Icons.directions_run;
        gradient = const [
          Color(0xFF0D47A1),
          Color(0xFF1565C0),
          Color(0xFF1E88E5),
        ];
      case _Status.waiting:
        title = _t(isTagalog, 'Monitoring', 'Nagmamasid');
        subtitle = _t(isTagalog, 'Waiting for data from the device...',
            'Naghihintay ng data mula sa device...');
        icon = Icons.monitor_heart;
        gradient = const [
          Color(0xFF455A64),
          Color(0xFF607D8B),
          Color(0xFF90A4AE),
        ];
      case _Status.offline:
        title = _t(isTagalog, 'Device Offline', 'Walang Koneksyon');
        subtitle = _t(isTagalog,
            'Showing the last saved data — this may not be current.',
            'Ipinapakita ang huling na-save na data — maaaring hindi ito kasalukuyan.');
        icon = Icons.signal_wifi_off;
        gradient = const [
          Color(0xFFE65100),
          Color(0xFFF57C00),
          Color(0xFFFFA726),
        ];
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2.5,
              ),
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 50),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.90),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Friendly status card ─────────────────────────────────────────────────

  String _formatDuration(bool isTagalog, Duration d) {
    if (d.inMinutes < 1) {
      return _t(isTagalog, 'less than a minute', 'wala pang isang minuto');
    }
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours} h ${d.inMinutes % 60} min';
  }

  Widget _buildLevelBar(bool isTagalog, _Status status) {
    const levels = [
      _Status.still,
      _Status.light,
      _Status.moving,
      _Status.vigorous,
    ];
    final idx = levels.indexOf(status);
    if (idx < 0) return const SizedBox.shrink();

    final color = _statusColor(status);
    final labels = [
      _t(isTagalog, 'Still', 'Nakatigil'),
      _t(isTagalog, 'Light', 'Banayad'),
      _t(isTagalog, 'Moving', 'Gumagalaw'),
      _t(isTagalog, 'Intense', 'Matindi'),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          for (var i = 0; i < levels.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= idx ? color : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          i == idx ? FontWeight.w800 : FontWeight.w500,
                      color: i == idx ? color : const Color(0xFF9EA8C2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isTagalog, DeviceData? data, _Status status) {
    final Color color = _statusColor(status);

    final String explanation;
    final String guidance;

    switch (status) {
      case _Status.sos:
        explanation = _t(isTagalog,
            'The emergency button was pressed on the device.',
            'Pinindot ang emergency button sa device.');
        guidance = _t(isTagalog,
            'Call or check on your loved one right away, then mark them safe from the Map tab.',
            'Tawagan o tingnan agad ang iyong mahal sa buhay, at markahan silang ligtas mula sa Map tab.');
      case _Status.fall:
        explanation = _t(isTagalog,
            'The device detected a possible fall.',
            'May na-detect na posibleng pagbagsak ang device.');
        guidance = _t(isTagalog,
            'Check on your loved one, then mark them safe from the Map tab once confirmed.',
            'Tingnan ang iyong mahal sa buhay, at markahan silang ligtas mula sa Map tab kapag nakumpirma.');
      case _Status.still:
        explanation = _t(isTagalog,
            'The device is not detecting any movement.',
            'Walang nade-detect na paggalaw ang device.');
        guidance = _t(isTagalog,
            'Normal during rest or sleep. If this lasts unusually long while your loved one should be awake, consider checking in.',
            'Normal ito habang nagpapahinga o natutulog. Kung tumagal ito nang hindi karaniwan habang dapat gising sila, subukang kumustahin.');
      case _Status.light:
        explanation = _t(isTagalog,
            'The device is picking up small movements, like sitting or shifting around.',
            'May maliliit na paggalaw na nakikita ang device, tulad ng pag-upo o paggalaw ng katawan.');
        guidance = _t(isTagalog,
            'Everything looks calm. No action needed.',
            'Mukhang kalmado ang lahat. Walang kailangang gawin.');
      case _Status.moving:
        explanation = _t(isTagalog,
            'The device is detecting steady movement, like walking around.',
            'May tuloy-tuloy na paggalaw na nakikita ang device, tulad ng paglalakad.');
        guidance = _t(isTagalog,
            'Your loved one is moving normally. No action needed.',
            'Normal na gumagalaw ang iyong mahal sa buhay. Walang kailangang gawin.');
      case _Status.vigorous:
        explanation = _t(isTagalog,
            'The device is detecting strong movement, like running or vigorous activity.',
            'May malakas na paggalaw na nakikita ang device, tulad ng pagtakbo o matinding aktibidad.');
        guidance = _t(isTagalog,
            'Likely just activity. If it seems unusual, consider checking in.',
            'Malamang ay aktibidad lang ito. Kung tila kakaiba, subukang kumustahin.');
      case _Status.waiting:
        explanation = _t(isTagalog,
            'No recent data from the device yet.',
            'Wala pang bagong data mula sa device.');
        guidance = _t(isTagalog,
            'Keep the wearable powered on and connected to WiFi.',
            'Panatilihing naka-on ang wearable at nakakonekta sa WiFi.');
      case _Status.offline:
        explanation = _t(isTagalog,
            'The device is offline. The information below is from the last data saved by the app.',
            'Offline ang device. Ang impormasyon sa ibaba ay mula sa huling na-save na data ng app.');
        guidance = _t(isTagalog,
            'Check that the wearable is powered on and connected to WiFi.',
            'Tingnan kung naka-on ang wearable at nakakonekta sa WiFi.');
    }

    final stillSince = _stillSince;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _t(isTagalog, 'Status', 'Estado'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2340),
                ),
              ),
              const Spacer(),
              if (status == _Status.offline)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.signal_wifi_off, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(
                      _t(isTagalog, 'Offline', 'Offline'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ],
                )
              else
                Text(
                  data?.lastSeenLabel ?? _t(isTagalog, 'Last seen unknown',
                      'Hindi alam ang huling ulat'),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9EA8C2)),
                ),
            ],
          ),
          _buildLevelBar(isTagalog, status),
          const SizedBox(height: 12),
          Text(
            explanation,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7A99),
              height: 1.4,
            ),
          ),
          if (status == _Status.still && stillSince != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  _t(
                      isTagalog,
                      'Still for ${_formatDuration(isTagalog, DateTime.now().difference(stillSince))}',
                      'Nakatigil nang ${_formatDuration(isTagalog, DateTime.now().difference(stillSince))}'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    guidance,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(_Status status) {
    switch (status) {
      case _Status.sos:
      case _Status.fall:
        return const Color(0xFFE53935);
      case _Status.still:
        return const Color(0xFF00897B);
      case _Status.light:
      case _Status.moving:
      case _Status.vigorous:
        return const Color(0xFF1565C0);
      case _Status.waiting:
        return const Color(0xFF607D8B);
      case _Status.offline:
        return const Color(0xFFE65100);
    }
  }

  // ─── Sensor readings (collapsed behind a panel) ───────────────────────────

  Widget _buildSensorDetails(
      BuildContext context, bool isTagalog, DeviceData? data, bool isOnline) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.12)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.straighten,
              color: Color(0xFF1565C0), size: 20),
          title: Text(
            _t(isTagalog, 'Sensor readings', 'Mga reading ng sensor'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2340),
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            _t(isTagalog,
                'Advanced — raw X, Y, Z values',
                'Advanced — raw na X, Y, Z values'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9EA8C2)),
          ),
          children: [
            if (data == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _t(isTagalog, 'No data from device yet.',
                      'Wala pang data mula sa device.'),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7A99)),
                ),
              )
            else ...[
              _AccelBar(
                  label: 'X Axis',
                  value: data.accelX,
                  max: 8,
                  axisColor: const Color(0xFF1565C0)),
              const SizedBox(height: 10),
              _AccelBar(
                  label: 'Y Axis',
                  value: data.accelY,
                  max: 8,
                  axisColor: const Color(0xFF1976D2)),
              const SizedBox(height: 10),
              _AccelBar(
                  label: 'Z Axis',
                  value: data.accelZ,
                  max: 8,
                  axisColor: const Color(0xFF42A5F5)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── How it works ──────────────────────────────────────────────────────────

  Widget _buildHowItWorks(bool isTagalog, {VoidCallback? onClose}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.info_outline,
                    color: Color(0xFF1565C0), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                _t(isTagalog, 'How Fall Detection Works',
                    'Paano Gumagana ang Fall Detection'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2340),
                  fontSize: 14,
                ),
              ),
              if (onClose != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      size: 20, color: Color(0xFF9EA8C2)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.sensors,
            text: _t(
                isTagalog,
                'The motion sensor on the device continuously measures movement on 3 axes.',
                'Patuloy na sinusukat ng sensor sa device ang paggalaw sa 3 axis.'),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.compare_arrows,
            text: _t(
                isTagalog,
                'When the total acceleration magnitude exceeds a threshold, a fall is detected.',
                'Kapag lumampas sa threshold ang kabuuang acceleration, may na-detect na pagbagsak.'),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.cloud_upload_outlined,
            text: _t(
                isTagalog,
                'The device sends this event to Firebase, and your app receives it instantly.',
                'Ipinapadala ng device ang event sa Firebase, at agad itong natatanggap ng iyong app.'),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.show_chart,
            text: _t(
                isTagalog,
                'The movement level (Still, Light, Moving, Intense) is worked out from how much the sensor readings change over the last few updates.',
                'Ang movement level (Nakatigil, Banayad, Gumagalaw, Matindi) ay kinukuwenta mula sa pagbabago ng sensor readings sa huling ilang update.'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDevice(BuildContext context, bool isTagalog) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.sensors, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _t(isTagalog, 'Movement', 'Paggalaw'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled,
                size: 48, color: Color(0xFF9EA8C2)),
            const SizedBox(height: 16),
            Text(
              _t(isTagalog, 'No device configured', 'Walang naka-set na device'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7A99)),
            ),
            const SizedBox(height: 8),
            Text(
              _t(isTagalog, 'Set up your device from the Home tab',
                  'I-set up ang device mula sa Home tab'),
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF9EA8C2)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _AccelBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color axisColor;

  const _AccelBar({
    required this.label,
    required this.value,
    required this.max,
    required this.axisColor,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = (value.abs() / max).clamp(0.0, 1.0);
    final Color barColor = normalized > 0.7
        ? const Color(0xFFE53935)
        : normalized > 0.4
            ? const Color(0xFFF57C00)
            : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: axisColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: axisColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2340),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(2)} g',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: barColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: normalized,
              backgroundColor: barColor.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF1565C0)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7A99),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}