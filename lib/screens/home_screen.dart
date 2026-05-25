// lib/screens/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/device_config_service.dart';
import '../models/device_data.dart';
import 'map_screen.dart';
import 'fall_detection_screen.dart';
import 'alerts_screen.dart';
import 'contacts_screen.dart';
import 'geofence_screen.dart';
import 'device_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  String? _deviceId;
  bool _isConfigured = false;
  bool _isLoading = true;
  final _deviceConfig = DeviceConfigService();

  @override
  void initState() {
    super.initState();
    _loadDeviceConfig();
  }

  Future<void> _loadDeviceConfig() async {
    final deviceId = await _deviceConfig.getDeviceId();
    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _isConfigured = deviceId != null && deviceId.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  Future<void> _openSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
    );
    _loadDeviceConfig();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }

    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';
    final deviceId = _deviceId ?? '';

    final screens = [
      _DashboardTab(deviceId: deviceId, isConfigured: _isConfigured, onSetup: _openSetup),
      MapScreen(deviceId: deviceId),
      FallDetectionScreen(deviceId: deviceId),
      AlertsScreen(deviceId: deviceId),
      GeofenceScreen(userId: userId, deviceId: deviceId),
      const ContactsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Home',
                  index: 0,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map,
                  label: 'Map',
                  index: 1,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.sensors_outlined,
                  activeIcon: Icons.sensors,
                  label: 'Fall',
                  index: 2,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.notifications_outlined,
                  activeIcon: Icons.notifications,
                  label: 'Alerts',
                  index: 3,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.location_on_outlined,
                  activeIcon: Icons.location_on,
                  label: 'Geofences',
                  index: 4,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.contacts_outlined,
                  activeIcon: Icons.contacts,
                  label: 'Contacts',
                  index: 5,
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Custom Nav Item ──────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1565C0).withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 22,
              color: isActive
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF9EA8C2),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF9EA8C2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Tab ────────────────────────────────────────────────────────────

class _DashboardTab extends StatefulWidget {
  final String deviceId;
  final bool isConfigured;
  final VoidCallback onSetup;
  const _DashboardTab({
    required this.deviceId,
    required this.isConfigured,
    required this.onSetup,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Timer? _refreshTimer;
  DeviceData? _latestData;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    final user = firebase.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.shield, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'GuardianNako Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.isConfigured ? Icons.bluetooth_connected : Icons.bluetooth,
              color: Colors.white,
            ),
            tooltip: widget.isConfigured ? 'Device configured' : 'Set up device',
            onPressed: widget.onSetup,
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: Colors.white),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Log out',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out',
                          style: TextStyle(color: Colors.white)),
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
          ),
        ],
      ),
      body: StreamBuilder<DeviceData>(
        stream: firebase.listenToDeviceData(widget.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _latestData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: const Color(0xFFE53935).withOpacity(0.6)),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load device data',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7A99),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Make sure your device is configured',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9EA8C2)),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasData) {
            _latestData = snapshot.data;
          }

          final data = _latestData;
          final isOnline = data?.deviceOnline ?? false;

          return RefreshIndicator(
            onRefresh: () async {},
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(0),
              children: [
                // ─── No Device Banner ───────────────────────────────────
                if (!widget.isConfigured)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_searching,
                            color: Colors.orange, size: 26),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No device connected',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFFE65100))),
                              SizedBox(height: 2),
                              Text('Tap to set up your Guardian wearable via Bluetooth',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7A99))),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: widget.onSetup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Set Up',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                // ─── Top Welcome Banner ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${user?.displayName?.split(' ').first ?? 'User'} ',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOnline
                                  ? '● Device is online and monitoring'
                                  : '○ Waiting for device...',
                              style: TextStyle(
                                fontSize: 13,
                                color: isOnline
                                    ? const Color(0xFFA5D6A7)
                                    : Colors.white60,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data?.lastSeenLabel ?? 'Last seen unknown',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Online badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? const Color(0xFF66BB6A)
                                    : Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Emergency Banner ─────────────────────────────
                      StreamBuilder<Map<String, dynamic>>(
                        stream: firebase.listenToEmergencyAlert(widget.deviceId),
                        builder: (context, snap) {
                          final emergencyData = snap.data ?? {};
                          final isEmergencyActive = emergencyData['active'] == true;
                          final emergencyReason =
                              emergencyData['reason'] as String? ?? '';
                          final isSOSButton = emergencyReason.contains('SOS button');

                          if (!isEmergencyActive) return const SizedBox.shrink();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE53935).withOpacity(0.35),
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
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSOSButton
                                        ? Icons.emergency
                                        : Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isSOSButton
                                            ? 'SOS ALERT!'
                                            : 'FALL DETECTED',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          letterSpacing: 0.3,
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
                                      firebase.clearEmergency(widget.deviceId),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.2),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                  ),
                                  child: const Text('Dismiss',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // ─── Section Label ────────────────────────────────
                      const Text(
                        'Device Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2340),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ─── Status Cards Grid ────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _StatusCard(
                              icon: Icons.location_on,
                              label: 'GPS Location',
                              value: data != null && (data.latitude != 0)
                                  ? '${data.latitude.toStringAsFixed(4)},\n${data.longitude.toStringAsFixed(4)}'
                                  : 'No signal',
                              color: const Color(0xFF1565C0),
                              isActive: (data?.latitude ?? 0) != 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatusCard(
                              icon: Icons.sensors,
                              label: 'Movement',
                              value: data != null
                                  ? 'X:${data.accelX.toStringAsFixed(1)}\nY:${data.accelY.toStringAsFixed(1)}'
                                  : '---',
                              color: const Color(0xFF1976D2),
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
                              label: 'Movement Status',
                              value: data?.fallDetected == true
                                  ? 'FALL\nDETECTED!'
                                  : 'Normal',
                              color: data?.fallDetected == true
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFF2E7D32),
                              isActive: data != null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatusCard(
                              icon: Icons.wifi,
                              label: 'Device Connectivity',
                              value: isOnline ? 'Connected' : 'Disconnected',
                              color: isOnline
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF9EA8C2),
                              isActive: isOnline,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ─── Quick Info ───────────────────────────────────
                      const Text(
                        'Quick Guide',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2340),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoTile(
                        icon: Icons.sensors,
                        title: 'Fall Detection',
                        subtitle: 'A sensor monitors movement 24/7',
                        color: const Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 8),
                      _InfoTile(
                        icon: Icons.location_on,
                        title: 'GPS Tracking',
                        subtitle: 'Live location updates from your device',
                        color: const Color(0xFF1976D2),
                      ),
                      const SizedBox(height: 8),
                      _InfoTile(
                        icon: Icons.notifications_active,
                        title: 'Emergency Alerts',
                        subtitle: 'Instant SOS and fall notifications',
                        color: const Color(0xFFE53935),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF43A047) : const Color(0xFF9EA8C2),
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
              color: Color(0xFF6B7A99),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Info Tile ─────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2340),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7A99),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}