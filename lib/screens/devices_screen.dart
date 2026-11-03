// lib/screens/devices_screen.dart

import 'package:flutter/material.dart';
import '../models/paired_device.dart';
import '../services/device_config_service.dart';
import '../services/firebase_service.dart';
import '../widgets/toast_notification.dart';
import '../widgets/battery_indicator.dart';
import 'device_setup_screen.dart';

/// Lists the signed-in user's paired devices and lets them add, switch to,
/// rename or remove a device. The active selection is a local preference.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _firebase = FirebaseService();
  final _deviceConfig = DeviceConfigService();
  String? _activeDeviceId;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    final id = await _deviceConfig.getActiveDeviceId();
    if (mounted) setState(() => _activeDeviceId = id);
  }

  Future<void> _setActive(String deviceId) async {
    await _deviceConfig.setActiveDeviceId(deviceId);
    if (mounted) setState(() => _activeDeviceId = deviceId);
  }

  void _toast(String title, String message,
      {IconData icon = Icons.check_circle_outline,
      Color color = const Color(0xFF2E7D32),
      Color background = const Color(0xFFE8F5E9)}) {
    if (!mounted) return;
    ToastNotification.show(
      context,
      title: title,
      message: message,
      icon: icon,
      color: color,
      background: background,
    );
  }

  Future<void> _rename(PairedDevice device) async {
    final controller = TextEditingController(text: device.deviceName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename device',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Device name',
            hintText: 'e.g. Lola\'s pendant',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    if (newName.isEmpty) {
      _toast('Device not renamed', 'Name cannot be empty.',
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA));
      return;
    }

    try {
      await _firebase.renameDevice(device.deviceId, newName);
      _toast('Device renamed', 'Now called "$newName".');
    } catch (e) {
      _toast('Rename failed', e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA));
    }
  }

  Future<void> _remove(PairedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove device',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Remove "${device.displayName}" from your account? '
          'You can pair it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _firebase.removeDevice(device.deviceId);
      if (_activeDeviceId == device.deviceId) {
        await _deviceConfig.clearActiveDeviceId();
        if (mounted) setState(() => _activeDeviceId = null);
      }
      _toast('Device removed', '"${device.displayName}" was unpaired.');
    } catch (e) {
      _toast('Remove failed', e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline,
          color: const Color(0xFFD32F2F),
          background: const Color(0xFFFDECEA));
    }
  }

  Future<void> _addDevice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
    );
    _loadActive();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Devices',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<List<PairedDevice>>(
        stream: _firebase.listenToDevices(),
        builder: (context, snap) {
          final devices = snap.data ?? const <PairedDevice>[];
          if (snap.connectionState == ConnectionState.waiting &&
              devices.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (devices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.devices, color: Color(0xFF9EA8C2), size: 44),
                      SizedBox(height: 12),
                      Text(
                        'No devices yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2340),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Add your Guardian wearable to start monitoring.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
                      ),
                    ],
                  ),
                ),
              for (final device in devices) ...[
                _DeviceTile(
                  device: device,
                  isActive: device.deviceId == _activeDeviceId,
                  onTap: () => _setActive(device.deviceId),
                  onRename: () => _rename(device),
                  onRemove: () => _remove(device),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _addDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Add device',
                    style: TextStyle(fontWeight: FontWeight.w700),
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

class _DeviceTile extends StatelessWidget {
  final PairedDevice device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle =
        device.wearerName.isNotEmpty ? device.wearerName : device.deviceId;
    final batteryPercent = simulatedBatteryPercent(device.deviceId);
    final color = batteryColor(batteryPercent);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF1565C0).withValues(alpha: 0.12)
                      : const Color(0xFF6B7A99).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.watch,
                  color: isActive
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF6B7A99),
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
                        Flexible(
                          child: Text(
                            device.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF1A2340),
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7A99)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(batteryIcon(batteryPercent), color: color, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    '$batteryPercent%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF9EA8C2)),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'remove') onRemove();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      Icon(Icons.edit_outlined,
                          size: 20, color: Color(0xFF1565C0)),
                      SizedBox(width: 12),
                      Text('Rename'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 20, color: Color(0xFFE53935)),
                      SizedBox(width: 12),
                      Text('Remove',
                          style: TextStyle(color: Color(0xFFE53935))),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
