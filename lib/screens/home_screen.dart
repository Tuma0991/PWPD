// lib/screens/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/firebase_service.dart';
import '../services/device_config_service.dart';
import '../services/language_service.dart';
import '../services/alert_sound_service.dart';
import '../models/device_data.dart';
import '../models/paired_device.dart';
import '../widgets/toast_notification.dart';
import '../main.dart'
    show consumePendingInitialMessage, setNotificationTapHandler;
import 'map_screen.dart';
import 'fall_detection_screen.dart';
import 'alerts_screen.dart';
import 'contacts_screen.dart';
import 'device_setup_screen.dart';
import 'devices_screen.dart';
import 'device_settings_screen.dart';
import 'alert_sound_screen.dart';
import 'account_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  List<PairedDevice> _devices = [];
  String? _activeDeviceId;
  String? _userId;
  bool _isConfigured = false;
  bool _isLoading = true;
  bool _fcmRegistered = false;
  final _deviceConfig = DeviceConfigService();
  final _firebase = FirebaseService();
  StreamSubscription? _authSub;
  StreamSubscription<List<PairedDevice>>? _devicesSub;

  // ─── Emergency dialog (shown once per emergency) ───────────────────────────
  StreamSubscription<Map<String, dynamic>>? _emergencySub;
  String? _emergencyListeningDeviceId;

  /// True once the dialog has been shown for the current emergency. Reset when
  /// the emergency is cleared ("Mark as Safe"), so the next one shows again.
  bool _emergencyDialogShown = false;
  bool _emergencyDialogOpen = false;

  /// Current emergency state, used for the "Mark as Safe" strip shown on the
  /// Movement / Alerts / Contacts tabs.
  bool _emergencyActive = false;
  String _emergencyReason = '';

  /// Plays a looping alarm while an emergency is active. Stops on Mark as Safe.
  final AudioPlayer _alertPlayer = AudioPlayer();

  /// Bumped on "View Map" to make MapScreen recenter and draw the route.
  final ValueNotifier<int> _recenterRequest = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _userId = _firebase.currentUser?.uid;
    _loadDevices();

    // Register this phone for push notifications when the deviceId changes
    setNotificationTapHandler((index) {
      if (mounted && index >= 0 && index <= 5) {
        setState(() => _currentIndex = index);
      }
    });

    // Consume notification that launched the app from terminated state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      consumePendingInitialMessage();
    });

    // Clean up FCM tokens on logout (currentUser is already null here, so
    // remove against the uid + device ids captured while signed in).
    _authSub = _firebase.authStateChanges.listen((user) {
      if (user == null && _userId != null) {
        _firebase.removeFcmTokensForDevices(
          _userId!,
          _devices.map((d) => d.deviceId).toList(),
        );
        _userId = null;
      }
    });
  }

  @override
  void dispose() {
    setNotificationTapHandler(null);
    _authSub?.cancel();
    _devicesSub?.cancel();
    _emergencySub?.cancel();
    _recenterRequest.dispose();
    _alertPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final legacy = await _deviceConfig.migrateLegacyDevice();
    String? legacyId = legacy?.deviceId;

    _devicesSub?.cancel();
    _devicesSub = _firebase.listenToDevices().listen((devices) {
      if (!mounted) return;

      // Backfill a pre-existing single device into Firestore once.
      final pendingId = legacyId;
      if (pendingId != null &&
          pendingId.isNotEmpty &&
          !devices.any((d) => d.deviceId == pendingId)) {
        _firebase.addDevice(pendingId, deviceName: legacy?.deviceName ?? '');
        legacyId = null;
        return; // the next snapshot will include it
      }

      _applyDevices(devices);

      if (!_fcmRegistered && devices.isNotEmpty) {
        _fcmRegistered = true;
        _firebase.registerFcmTokenForAllDevices();
      }
    });
  }

  Future<void> _applyDevices(List<PairedDevice> devices) async {
    var activeId = await _deviceConfig.getActiveDeviceId();
    if (activeId == null ||
        activeId.isEmpty ||
        !devices.any((d) => d.deviceId == activeId)) {
      activeId = devices.isNotEmpty ? devices.first.deviceId : null;
      if (activeId != null) await _deviceConfig.setActiveDeviceId(activeId);
    }
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _activeDeviceId = activeId;
      _isConfigured = devices.isNotEmpty;
      _isLoading = false;
    });
    _subscribeToEmergency(activeId ?? '');
  }

  /// Re-reads the active device and resubscribes after a sub-screen may have
  /// switched or added a device (Firestore stream already covers additions).
  Future<void> _refreshDevices() => _applyDevices(_devices);

  Future<void> _switchDevice(String deviceId) async {
    if (deviceId == _activeDeviceId) return;
    await _deviceConfig.setActiveDeviceId(deviceId);
    _subscribeToEmergency(deviceId);
    if (mounted) setState(() => _activeDeviceId = deviceId);
  }

  // ─── Emergency dialog logic ────────────────────────────────────────────────

  void _subscribeToEmergency(String deviceId) {
    if (deviceId == _emergencyListeningDeviceId) return;
    _emergencySub?.cancel();
    _emergencySub = null;
    _emergencyListeningDeviceId = deviceId;
    _emergencyDialogShown = false;
    if (deviceId.isEmpty) return;
    _emergencySub =
        _firebase.listenToEmergencyAlert(deviceId).listen(_onEmergencyEvent);
  }

  void _onEmergencyEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final isActive = event['active'] == true;
    final reason = event['reason'] as String? ?? '';

    if (_emergencyActive != isActive || _emergencyReason != reason) {
      setState(() {
        _emergencyActive = isActive;
        _emergencyReason = reason;
      });
    }

    if (!isActive) {
      // Cleared (Mark as Safe from anywhere) — allow the next emergency to
      // show its dialog, and close this one if it's still open.
      _emergencyDialogShown = false;
      _stopAlertSound();
      if (_emergencyDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }

    // The device writes emergency fields one at a time, so wait until the
    // reason has arrived, and only ever show the dialog once.
    if (reason.isEmpty || _emergencyDialogShown) return;
    _emergencyDialogShown = true;
    _startAlertSound();
    _showEmergencyDialog(reason);
  }

  Future<void> _startAlertSound() async {
    try {
      final source = await AlertSoundService.instance.getAlertSource();
      await _alertPlayer.setReleaseMode(ReleaseMode.loop);
      await _alertPlayer.play(source, volume: 1.0);
    } catch (e) {
      debugPrint('Failed to play alert sound: $e');
    }
  }

  Future<void> _stopAlertSound() async {
    try {
      await _alertPlayer.stop();
    } catch (_) {
      // Ignore — the player may already be stopped/disposed.
    }
  }

  Future<void> _showEmergencyDialog(String reason) async {
    final isSOS = reason.contains('SOS button');
    final isFall = reason.contains('Fall');
    final title = isSOS
        ? 'SOS ALERT!'
        : isFall
            ? 'FALL DETECTED'
            : 'EMERGENCY ALERT!';
    final message = isSOS
        ? 'The emergency button was pressed on the device.'
        : isFall
            ? 'A possible fall was detected.'
            : 'An emergency alert was triggered.';

    _emergencyDialogOpen = true;
    final viewMap = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSOS ? Icons.emergency : Icons.warning_amber_rounded,
                color: const Color(0xFFE53935),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFFE53935),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '$message\n\nCheck on your loved one, then tap "Mark as Safe" '
          'once confirmed.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Dismiss',
              style: TextStyle(
                color: Color(0xFF6B7A99),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.map, size: 18),
            label: const Text(
              'View Map',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    _emergencyDialogOpen = false;

    if (viewMap == true && mounted) {
      setState(() => _currentIndex = 1);
      // Fire after the tab switch so the map recenters while visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recenterRequest.value++;
      });
    }
  }

  Widget _buildSafeStrip(String deviceId) {
    final isSOS = _emergencyReason.contains('SOS button');
    final isFall = _emergencyReason.contains('Fall');
    final title = isSOS
        ? 'SOS ALERT!'
        : isFall
            ? 'FALL DETECTED'
            : 'EMERGENCY ALERT!';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      color: const Color(0xFFE53935),
      child: Row(
        children: [
          Icon(
            isSOS ? Icons.emergency : Icons.warning_amber_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _firebase.clearEmergency(deviceId),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Future<void> _openSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
    );
    _refreshDevices();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }

    final firebase = FirebaseService();
    final userId = firebase.currentUser?.uid ?? '';
    final deviceId = _activeDeviceId ?? '';

    final screens = [
      _DashboardTab(
          deviceId: deviceId,
          devices: _devices,
          activeDeviceId: _activeDeviceId,
          isConfigured: _isConfigured,
          onSetup: _openSetup,
          onSelectDevice: _switchDevice,
          onDevicesChanged: _refreshDevices,
          isActive: _currentIndex == 0),
      MapScreen(
          userId: userId,
          deviceId: deviceId,
          isActive: _currentIndex == 1,
          recenterRequest: _recenterRequest),
      FallDetectionScreen(deviceId: deviceId, isActive: _currentIndex == 2),
      AlertsScreen(deviceId: deviceId),
      const ContactsScreen(),
    ];

    // Map and Dashboard have their own Mark as Safe; the other tabs share this.
    final showSafeStrip = _emergencyActive &&
        _emergencyReason.isNotEmpty &&
        (_currentIndex == 2 || _currentIndex == 3 || _currentIndex == 4);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: screens,
            ),
          ),
          if (showSafeStrip) _buildSafeStrip(deviceId),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left half (equal width to the right half)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.map_outlined,
                          activeIcon: Icons.map,
                          label: 'Map',
                          index: 1,
                          currentIndex: _currentIndex,
                          onTap: (i) => setState(() => _currentIndex = i),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.sensors_outlined,
                          activeIcon: Icons.sensors,
                          label: 'Movement',
                          index: 2,
                          currentIndex: _currentIndex,
                          onTap: (i) => setState(() => _currentIndex = i),
                        ),
                      ),
                    ],
                  ),
                ),
                // Dashboard — fixed width, always the exact center of the bar
                SizedBox(
                  width: 76,
                  child: _CenterNavItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    index: 0,
                    currentIndex: _currentIndex,
                    onTap: (i) => setState(() => _currentIndex = i),
                  ),
                ),
                // Right half
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.notifications_outlined,
                          activeIcon: Icons.notifications,
                          label: 'Alerts',
                          index: 3,
                          currentIndex: _currentIndex,
                          onTap: (i) => setState(() => _currentIndex = i),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.contacts_outlined,
                          activeIcon: Icons.contacts,
                          label: 'Contacts',
                          index: 4,
                          currentIndex: _currentIndex,
                          onTap: (i) => setState(() => _currentIndex = i),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Center (Dashboard) Nav Item ──────────────────────────────────────────────

class _CenterNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CenterNavItem({
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
    const blue = Color(0xFF1565C0);

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isActive
                    ? const [Color(0xFF1E88E5), Color(0xFF0D47A1)]
                    : const [Color(0xFF5C9BE0), Color(0xFF1565C0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: blue.withValues(alpha: isActive ? 0.40 : 0.25),
                  blurRadius: isActive ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isActive ? activeIcon : icon,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isActive ? blue : const Color(0xFF6B7A99),
            ),
          ),
        ],
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
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1565C0).withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 22,
              color:
                  isActive ? const Color(0xFF1565C0) : const Color(0xFF9EA8C2),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF9EA8C2),
                ),
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
  final List<PairedDevice> devices;
  final String? activeDeviceId;
  final bool isConfigured;
  final VoidCallback onSetup;
  final ValueChanged<String> onSelectDevice;
  final VoidCallback onDevicesChanged;
  final bool isActive;
  const _DashboardTab({
    required this.deviceId,
    required this.devices,
    required this.activeDeviceId,
    required this.isConfigured,
    required this.onSetup,
    required this.onSelectDevice,
    required this.onDevicesChanged,
    this.isActive = true,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> with OfflineToastMixin {
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
    disposeOfflineToast();
    super.dispose();
  }

  Widget _buildDeviceSwitcher(BuildContext context) {
    final active = widget.devices.firstWhere(
      (d) => d.deviceId == widget.activeDeviceId,
      orElse: () => widget.devices.first,
    );
    return PopupMenuButton<String>(
      tooltip: 'Switch device',
      onSelected: (value) {
        if (value == '__manage__') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DevicesScreen()),
          ).then((_) => widget.onDevicesChanged());
        } else {
          widget.onSelectDevice(value);
        }
      },
      itemBuilder: (context) => [
        for (final d in widget.devices)
          PopupMenuItem(
            value: d.deviceId,
            child: Row(
              children: [
                Icon(
                  d.deviceId == widget.activeDeviceId
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: d.deviceId == widget.activeDeviceId
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF9EA8C2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    d.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__manage__',
          child: Row(
            children: [
              Icon(Icons.devices, size: 18, color: Color(0xFF1565C0)),
              SizedBox(width: 10),
              Text('Manage devices',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.watch, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                active.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
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
            ClipOval(
              child: Image.asset(
                'lib/images/Logo.png',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'GuardianNako',
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
          if (widget.devices.isNotEmpty) _buildDeviceSwitcher(context),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'More',
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SettingsScreen(
                      userId: firebase.currentUser?.uid ?? '',
                      deviceId: widget.deviceId,
                      onDevicesChanged: widget.onDevicesChanged,
                    ),
                  ),
                );
              } else if (value == 'about') {
                _showAboutDialog(context);
              } else if (value == 'logout') {
                final shouldLogout = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
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
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_outlined,
                      size: 20, color: Color(0xFF1565C0)),
                  SizedBox(width: 12),
                  Text('Settings'),
                ]),
              ),
              PopupMenuItem(
                value: 'about',
                child: Row(children: [
                  Icon(Icons.info_outline, size: 20, color: Color(0xFF1565C0)),
                  SizedBox(width: 12),
                  Text('About Us'),
                ]),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_outlined,
                      size: 20, color: Color(0xFFE53935)),
                  SizedBox(width: 12),
                  Text('Log out', style: TextStyle(color: Color(0xFFE53935))),
                ]),
              ),
            ],
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

          if (snapshot.hasError && _latestData == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48,
                      color: const Color(0xFFE53935).withValues(alpha: 0.6)),
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
          // Has reported before, but the heartbeat is stale → show last data.
          final isOffline = data != null && data.timestamp > 0 && !isOnline;

          syncOfflineToast(
            offline: isOffline,
            active: widget.isActive,
            title: 'Device is offline',
            message:
                'Showing the last data saved by the app — it may not be current.',
          );

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
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
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
                              Text(
                                  'Tap to set up your Guardian wearable via Bluetooth',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF6B7A99))),
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
                                  : isOffline
                                      ? '○ Device offline — showing last saved data'
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
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25)),
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
                      // ─── Emergency Banner (Mark as Safe only) ─────────
                      // The one-time alert dialog lives in HomeScreen; this
                      // banner stays until the emergency is marked safe.
                      StreamBuilder<Map<String, dynamic>>(
                        stream:
                            firebase.listenToEmergencyAlert(widget.deviceId),
                        builder: (context, snap) {
                          final emergencyData = snap.data ?? {};
                          final isEmergencyActive =
                              emergencyData['active'] == true;
                          final emergencyReason =
                              emergencyData['reason'] as String? ?? '';
                          final isSOSButton =
                              emergencyReason.contains('SOS button');
                          final isFall = emergencyReason.contains('Fall');

                          if (!isEmergencyActive) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE53935)
                                      .withValues(alpha: 0.35),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isSOSButton
                                            ? 'SOS ALERT!'
                                            : isFall
                                                ? 'FALL DETECTED'
                                                : 'EMERGENCY ALERT!',
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
                                            : isFall
                                                ? 'Fall event detected!'
                                                : 'Emergency alert triggered!',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      firebase.clearEmergency(widget.deviceId),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFFE53935),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  child: const Text('Mark as Safe',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
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
                              isActive: isOnline && (data?.latitude ?? 0) != 0,
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
                              isActive: data != null && isOnline,
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
                              isActive: data != null && isOnline,
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
                      const _InfoTile(
                        icon: Icons.sensors,
                        title: 'Fall Detection',
                        subtitle:
                            'A sensor monitors movement patterns to detect falls in real-time',
                        color: Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 8),
                      const _InfoTile(
                        icon: Icons.location_on,
                        title: 'GPS Tracking',
                        subtitle: 'Live location updates from your device',
                        color: Color(0xFF1976D2),
                      ),
                      const SizedBox(height: 8),
                      const _InfoTile(
                        icon: Icons.notifications_active,
                        title: 'Emergency Alerts',
                        subtitle: 'Instant alert notifications',
                        color: Color(0xFFE53935),
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
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF43A047)
                      : const Color(0xFF9EA8C2),
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
            color: Colors.black.withValues(alpha: 0.04),
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
              color: color.withValues(alpha: 0.10),
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

// ─── About Us dialog ──────────────────────────────────────────────────────────

void _showAboutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.shield, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text('GuardianNako', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      content: const Text(
        // TODO: replace with your own team / project description
        'GuardianNako is a wearable safety companion that provides real-time '
        'GPS tracking, fall detection and emergency alerts to keep your loved '
        'ones safe.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

// ─── Settings screen ──────────────────────────────────────────────────────────

class _SettingsScreen extends StatelessWidget {
  final String userId;
  final String deviceId;
  final VoidCallback onDevicesChanged;
  const _SettingsScreen({
    required this.userId,
    required this.deviceId,
    required this.onDevicesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined,
                  color: Color(0xFF1565C0)),
              title: const Text('Account',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Name, email and password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AccountSettingsScreen(),
                  ),
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading:
                  const Icon(Icons.settings_outlined, color: Color(0xFF1565C0)),
              title: const Text('Device Settings',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Wearer photo, name and device setup'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceSettingsScreen(
                      userId: userId,
                      deviceId: deviceId,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.devices, color: Color(0xFF1565C0)),
              title: const Text('Devices',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Add, switch or remove paired devices'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DevicesScreen()),
                ).then((_) => onDevicesChanged());
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: LanguageService.isTagalog,
            builder: (context, isTagalog, _) {
              return Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  secondary:
                      const Icon(Icons.translate, color: Color(0xFF1565C0)),
                  title: const Text('Language',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(isTagalog ? 'Filipino' : 'English'),
                  value: isTagalog,
                  activeThumbColor: const Color(0xFF1565C0),
                  onChanged: (value) => LanguageService.isTagalog.value = value,
                ),
              );
            },
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const Icon(Icons.music_note, color: Color(0xFF1565C0)),
              title: const Text('Alert sound',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle:
                  const Text('Choose the alarm tone for emergency alerts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertSoundScreen()),
                );
              },
            ),
          ),
          // Add more settings tiles here (notifications, units, etc.)
        ],
      ),
    );
  }
}
