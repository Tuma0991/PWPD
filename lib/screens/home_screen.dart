// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';
import '../theme.dart';
import 'map_screen.dart';
import 'fall_detection_screen.dart';
import 'alerts_screen.dart';
import 'contacts_screen.dart';
import 'geofence_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final String _deviceId = 'esp32_device_1';

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';
    
    final screens = [
      _DashboardTab(deviceId: _deviceId),
      MapScreen(deviceId: _deviceId),
      FallDetectionScreen(deviceId: _deviceId),
      AlertsScreen(deviceId: _deviceId),
      GeofenceScreen(userId: userId, deviceId: _deviceId),
      const ContactsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sensors_outlined),
              activeIcon: Icon(Icons.sensors),
              label: 'Sensors',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_on_outlined),
              activeIcon: Icon(Icons.location_on),
              label: 'Geofences',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              activeIcon: Icon(Icons.contacts),
              label: 'Contacts',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Tab ───────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final String deviceId;
  const _DashboardTab({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final user = firebase.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Guardian'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Log out'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );

              if (shouldLogout != true) return;

              try {
                await firebase.signOut();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logout failed: ${e.toString()}')),
                  );
                }
              }
            },
          )
        ],
      ),
      body: StreamBuilder<DeviceData>(
        stream: firebase.listenToDeviceData(deviceId),
        builder: (context, snapshot) {
          // Handle connection states
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Handle errors
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: AppTheme.danger.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load device data',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your device is configured',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data;
          final isOnline = data?.deviceOnline ?? false;

          return RefreshIndicator(
            onRefresh: () async {},
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Welcome
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${user?.displayName?.split(' ').first ?? 'User'} 👋',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isOnline
                                ? 'Device is online and monitoring'
                                : 'Waiting for device...',
                            style: TextStyle(
                              fontSize: 13,
                              color: isOnline
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data?.lastSeenLabel ?? 'Last seen unknown',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Device status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isOnline ? AppTheme.success : AppTheme.textSecondary)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (isOnline
                                  ? AppTheme.success
                                  : AppTheme.textSecondary)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isOnline
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ─── Emergency Banner ──────────────────────────────────────
                StreamBuilder<Map<String, dynamic>>(
                  stream: firebase.listenToEmergencyAlert(deviceId),
                  builder: (context, snap) {
                    final emergencyData = snap.data ?? {};
                    final isEmergencyActive = emergencyData['active'] == true;
                    final emergencyReason = emergencyData['reason'] as String? ?? '';
                    final isSOSButton = emergencyReason.contains('SOS button');
                    
                    if (!isEmergencyActive) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.danger.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSOSButton ? Icons.emergency : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSOSButton ? '🚨 SOS ALERT!' : '⚠️ FALL DETECTED',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isSOSButton 
                                    ? 'Emergency button was pressed!'
                                    : 'Fall event detected!',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                firebase.clearEmergency(deviceId),
                            child: const Text('Dismiss',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // ─── Status Cards ──────────────────────────────────────────
                const Text(
                  'Device Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _StatusCard(
                        icon: Icons.location_on,
                        label: 'GPS',
                        value: data != null
                            ? '${data.latitude.toStringAsFixed(4)}, ${data.longitude.toStringAsFixed(4)}'
                            : 'No signal',
                        color: AppTheme.primary,
                        isActive: (data?.latitude ?? 0) != 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatusCard(
                        icon: Icons.sensors,
                        label: 'Accel',
                        value: data != null
                            ? 'X:${data.accelX.toStringAsFixed(1)} Y:${data.accelY.toStringAsFixed(1)}'
                            : '---',
                        color: AppTheme.accent,
                        isActive: data != null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _StatusCard(
                        icon: Icons.personal_injury_outlined,
                        label: 'Fall Status',
                        value: data?.fallDetected == true
                            ? 'FALL DETECTED!'
                            : 'Normal',
                        color: data?.fallDetected == true
                            ? AppTheme.danger
                            : AppTheme.success,
                        isActive: data != null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatusCard(
                        icon: Icons.wifi,
                        label: 'Connection',
                        value: isOnline ? 'Connected' : 'Disconnected',
                        color: isOnline ? AppTheme.success : AppTheme.textSecondary,
                        isActive: isOnline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isActive;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.success : AppTheme.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}


