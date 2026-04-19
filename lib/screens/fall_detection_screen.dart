// lib/screens/fall_detection_screen.dart

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';
import '../theme.dart';

class FallDetectionScreen extends StatelessWidget {
  final String deviceId;
  const FallDetectionScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('Fall Detection')),
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
              final data = snapshot.data;
              final isFall = isEmergencyActive && (isSOSButton || isFallDetection || (data?.fallDetected ?? false));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ─── Fall Status Hero ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isFall
                        ? [AppTheme.danger, const Color(0xFFB71C1C)]
                        : [AppTheme.primary, AppTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (isFall ? AppTheme.danger : AppTheme.primary)
                          .withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      isFall
                          ? (isSOSButton ? Icons.emergency : Icons.personal_injury)
                          : Icons.directions_walk,
                      color: Colors.white,
                      size: 64,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isFall 
                          ? (isSOSButton ? '🚨 SOS ALERT!' : '⚠️ FALL DETECTED!')
                          : 'Normal Activity',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isFall
                          ? (isSOSButton 
                              ? 'Emergency button was pressed on the device!'
                              : 'An abnormal movement was detected by the device.')
                          : 'The wearer appears to be safe and moving normally.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isFall) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.danger,
                        ),
                        onPressed: () => firebase.clearEmergency(deviceId),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as Safe'),
                      )
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Accelerometer Data ────────────────────────────────────
              const Text(
                'Accelerometer Readings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              if (data == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No data from device yet.\nMake sure the ESP32 is powered on and connected to WiFi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else ...[
                _AccelBar(label: 'X Axis', value: data.accelX, max: 20),
                const SizedBox(height: 10),
                _AccelBar(label: 'Y Axis', value: data.accelY, max: 20),
                const SizedBox(height: 10),
                _AccelBar(label: 'Z Axis', value: data.accelZ, max: 20),
              ],

              const SizedBox(height: 24),

              // ─── How It Works ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.cardShadow,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    )
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'How Fall Detection Works',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    _InfoRow(
                        icon: Icons.sensors,
                        text:
                            'The MPU6050 accelerometer on the ESP32 continuously measures movement on 3 axes.'),
                    SizedBox(height: 8),
                    _InfoRow(
                        icon: Icons.compare_arrows,
                        text:
                            'When the total acceleration magnitude exceeds a threshold, a fall is detected.'),
                    SizedBox(height: 8),
                    _InfoRow(
                        icon: Icons.cloud_upload_outlined,
                        text:
                            'The ESP32 sends this event to Firebase, and your app receives it instantly.'),
                  ],
                ),
              ),
            ],
          );
            },
          );
        },
      ),
    );
  }
}

class _AccelBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;

  const _AccelBar({
    required this.label,
    required this.value,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = (value.abs() / max).clamp(0.0, 1.0);
    final color = normalized > 0.7
        ? AppTheme.danger
        : normalized > 0.4
            ? AppTheme.warning
            : AppTheme.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: AppTheme.cardShadow,
              blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
              Text(
                '${value.toStringAsFixed(2)} m/s²',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: normalized,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
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
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
          ),
        ),
      ],
    );
  }
}
