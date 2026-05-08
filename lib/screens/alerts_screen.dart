// lib/screens/alerts_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';

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

  @override
  void initState() {
    super.initState();
    _subscribeToEmergencyEvents();
  }

  @override
  void dispose() {
    _emergencySubscription?.cancel();
    super.dispose();
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

      final isNewEmergency = isEmergencyActive &&
          (!_previousEmergencyActive ||
              emergencyReason != _previousEmergencyReason);

      _previousEmergencyActive = isEmergencyActive;
      _previousEmergencyReason = emergencyReason;

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
                            color: const Color(0xFF1565C0).withOpacity(0.08),
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

                return Column(
                  children: [
                    // Summary bar
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      color: const Color(0xFF1565C0),
                      child: Row(
                        children: [
                          _AlertSummaryChip(
                            label: '${alerts.where((a) => a['type'] == 'fall').length} Falls',
                            color: const Color(0xFFEF5350),
                            icon: Icons.personal_injury,
                          ),
                          const SizedBox(width: 10),
                          _AlertSummaryChip(
                            label: '${alerts.where((a) => a['type'] == 'sos').length} SOS',
                            color: const Color(0xFFFFA726),
                            icon: Icons.warning_amber,
                          ),
                          const Spacer(),
                          Text(
                            '${alerts.length} total',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
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
                        child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                        child: ListView.separated(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        itemCount: alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final alert = alerts[i];
                          final type = alert['type'] ?? 'unknown';
                          final message = alert['message'] ?? 'Alert';
                          final ts = alert['timestamp'];
                          final isFall = type == 'fall';
                          final color = isFall
                              ? const Color(0xFFE53935)
                              : const Color(0xFFF57C00);

                          String timeStr = 'Unknown time';
                          if (ts != null) {
                            try {
                              final dt = (ts as dynamic).toDate();
                              timeStr = DateFormat('MMM d, y · h:mm a').format(dt);
                            } catch (_) {}
                          }

                          return Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: color.withOpacity(0.15), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.06),
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
                                    color: color.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isFall
                                        ? Icons.personal_injury
                                        : Icons.warning_amber,
                                    color: color,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.10),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isFall ? 'FALL' : 'SOS',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
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
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A2340),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 12,
                                              color: Color(0xFF9EA8C2)),
                                          const SizedBox(width: 4),
                                          Text(
                                            timeStr,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF9EA8C2),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: color.withOpacity(0.4), size: 18),
                              ],
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
}

class _AlertSummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _AlertSummaryChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
