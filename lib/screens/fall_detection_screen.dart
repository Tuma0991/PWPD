// lib/screens/fall_detection_screen.dart

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';

class FallDetectionScreen extends StatelessWidget {
  final String deviceId;
  const FallDetectionScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.sensors, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Fall Detection',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
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
              final data = snapshot.data;
              final isFall = isEmergencyActive &&
                  (isSOSButton ||
                      isFallDetection ||
                      (data?.fallDetected ?? false));

              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(0),
                children: [
                  // ─── Fall Status Hero ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isFall
                            ? [
                                const Color(0xFFB71C1C),
                                const Color(0xFFE53935),
                                const Color(0xFFEF5350),
                              ]
                            : [
                                const Color(0xFF1565C0),
                                const Color(0xFF1E88E5),
                                const Color(0xFF42A5F5),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Animated status circle
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2.5,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              isFall
                                  ? (isSOSButton
                                      ? Icons.emergency
                                      : Icons.personal_injury)
                                  : Icons.directions_walk,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isFall
                              ? (isSOSButton
                                  ? '🚨 SOS ALERT!'
                                  : '⚠️ FALL DETECTED!')
                              : '✅ Normal Activity',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isFall
                                ? (isSOSButton
                                    ? 'Emergency button was pressed on the device!'
                                    : 'An abnormal movement was detected.')
                                : 'The wearer appears safe and moving normally.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.90),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (isFall) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFFE53935),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                              ),
                              onPressed: () =>
                                  firebase.clearEmergency(deviceId),
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 18),
                              label: const Text(
                                'Mark as Safe',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── Accelerometer Data ────────────────────────
                        const Text(
                          'Accelerometer Readings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2340),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Real-time movement data from MPU6050 sensor',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF6B7A99)),
                        ),
                        const SizedBox(height: 14),

                        if (data == null)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'No data from device yet.\nMake sure the ESP32 is powered on and connected to WiFi.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF6B7A99), fontSize: 13),
                              ),
                            ),
                          )
                        else ...[
                          _AccelBar(
                              label: 'X Axis',
                              value: data.accelX,
                              max: 20,
                              axisColor: const Color(0xFF1565C0)),
                          const SizedBox(height: 10),
                          _AccelBar(
                              label: 'Y Axis',
                              value: data.accelY,
                              max: 20,
                              axisColor: const Color(0xFF1976D2)),
                          const SizedBox(height: 10),
                          _AccelBar(
                              label: 'Z Axis',
                              value: data.accelZ,
                              max: 20,
                              axisColor: const Color(0xFF42A5F5)),
                        ],

                        const SizedBox(height: 24),

                        // ─── How It Works ──────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: const Color(0xFF1565C0).withOpacity(0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1565C0).withOpacity(0.06),
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
                                      color: const Color(0xFF1565C0)
                                          .withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.info_outline,
                                        color: Color(0xFF1565C0), size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'How Fall Detection Works',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A2340),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const _InfoRow(
                                  icon: Icons.sensors,
                                  text:
                                      'The MPU6050 accelerometer on the ESP32 continuously measures movement on 3 axes.'),
                              const SizedBox(height: 10),
                              const _InfoRow(
                                  icon: Icons.compare_arrows,
                                  text:
                                      'When the total acceleration magnitude exceeds a threshold, a fall is detected.'),
                              const SizedBox(height: 10),
                              const _InfoRow(
                                  icon: Icons.cloud_upload_outlined,
                                  text:
                                      'The ESP32 sends this event to Firebase, and your app receives it instantly.'),
                            ],
                          ),
                        ),
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
  }
}

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: axisColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: axisColor.withOpacity(0.12)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: barColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(2)} m/s²',
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
              backgroundColor: barColor.withOpacity(0.10),
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
            color: const Color(0xFF1565C0).withOpacity(0.10),
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