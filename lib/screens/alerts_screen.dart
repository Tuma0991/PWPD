// lib/screens/alerts_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../theme.dart';

class AlertsScreen extends StatelessWidget {
  final String deviceId;
  const AlertsScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert History'),
        actions: [
          // Listen to live emergency and log it
          StreamBuilder<Map<String, dynamic>>(
            stream: firebase.listenToEmergencyAlert(deviceId),
            builder: (context, snap) {
              final emergencyData = snap.data ?? {};
              final isEmergencyActive = emergencyData['active'] == true;
              final emergencyReason = emergencyData['reason'] as String? ?? '';
              
              if (isEmergencyActive && userId.isNotEmpty) {
                // Auto log to Firestore with appropriate type
                final isSOSButton = emergencyReason.contains('SOS button');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  firebase.logAlert(userId, {
                    'type': isSOSButton ? 'sos' : 'fall',
                    'message': isSOSButton 
                        ? 'Emergency SOS button pressed'
                        : 'Fall detected by ESP32 device',
                    'deviceId': deviceId,
                    'reason': emergencyReason,
                  });
                });
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: userId.isEmpty
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: firebase.getAlertHistory(userId),
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
                        Icon(Icons.notifications_none,
                            size: 64,
                            color: AppTheme.textSecondary.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        const Text(
                          'No alerts yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Emergency events from your device\nwill appear here.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final alert = alerts[i];
                    final type = alert['type'] ?? 'unknown';
                    final message = alert['message'] ?? 'Alert';
                    final ts = alert['timestamp'];
                    final isFall = type == 'fall';
                    final color =
                        isFall ? AppTheme.danger : AppTheme.warning;

                    String timeStr = 'Unknown time';
                    if (ts != null) {
                      try {
                        final dt = (ts as dynamic).toDate();
                        timeStr = DateFormat('MMM d, y · h:mm a').format(dt);
                      } catch (_) {}
                    }

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: color.withOpacity(0.2), width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: AppTheme.cardShadow,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFall
                                  ? Icons.personal_injury
                                  : Icons.warning_amber,
                              color: color,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isFall
                                      ? 'Fall Detected'
                                      : 'Emergency Alert',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  message,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppTheme.textSecondary, size: 18),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
