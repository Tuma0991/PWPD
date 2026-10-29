import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';
import '../services/device_config_service.dart';
import '../services/firebase_service.dart';
import '../widgets/toast_notification.dart';

enum SetupStep { scan, enterWifi, provisioning, success, error }

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final _ble = BleProvisioningService();
  final _deviceConfig = DeviceConfigService();
  final _firebase = FirebaseService();

  SetupStep _step = SetupStep.scan;
  String? _errorMessage;

  // BLE scan
  StreamSubscription<ScanResult>? _scanSub;
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  ScanResult? _selectedDevice;

  // WiFi entry
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  // Provisioning result
  String? _provisionedDeviceId;
  String _provisioningStatus = '';

  // Bluetooth adapter tracking (for the "Bluetooth is off" notification)
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool? _btOn;

  void _showBluetoothOffToast() {
    if (!mounted) return;
    ToastNotification.show(
      context,
      title: 'Bluetooth is off',
      message: 'Turn on Bluetooth to scan for your Guardian device.',
      icon: Icons.bluetooth_disabled,
      owner: this,
    );
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    ToastNotification.dismiss(owner: this);
    _scanSub?.cancel();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Live Bluetooth state: toast when it's switched off, dismiss when on.
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      final on = state == BluetoothAdapterState.on;
      final wasOn = _btOn;
      _btOn = on;
      if (on) {
        ToastNotification.dismiss(owner: this);
      } else if (wasOn == true && _step == SetupStep.scan) {
        setState(() => _isScanning = false);
        _showBluetoothOffToast();
      }
    });
    _startScan();
  }

  Future<bool> _checkPermissions() async {
    // Android 12+ requires BLUETOOTH_SCAN at runtime.
    // Older Android requires ACCESS_FINE_LOCATION for BLE.
    if (Platform.isAndroid) {
      final btScan = await Permission.bluetoothScan.status;
      final btConnect = await Permission.bluetoothConnect.status;

      if (btScan.isDenied || btConnect.isDenied) {
        final results = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        if (results.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
          if (mounted) {
            setState(() {
              _errorMessage = 'BLE permissions denied. '
                  'Please grant Nearby Devices permission in App Settings.';
            });
          }
          return false;
        }
      }

      // On Android < 13, location services must be ON for BLE scanning.
      // On Android 13+, neverForLocation flag skips this — but our manifest
      // doesn't set that flag, so we check anyway.
      final location = await Permission.location.status;
      if (location.isDenied) {
        await Permission.location.request();
        if (await Permission.location.status.isDenied) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Location permission is required for BLE scanning.';
            });
          }
          return false;
        }
      }
    }

    // iOS requires Bluetooth permission (handled by flutter_blue_plus Info.plist).
    return true;
  }

  Future<void> _startScan() async {
    setState(() {
      _step = SetupStep.scan;
      _scanResults.clear();
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      // Guard against platforms without Bluetooth (desktop, emulator, etc.).
      // On such devices `adapterState`/`startScan` throw, which used to surface
      // as an unhandled "Invalid argument(s)" error.
      if (!await FlutterBluePlus.isSupported) {
        _btOn = false;
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _errorMessage = 'Bluetooth is not supported on this device.';
        });
        return;
      }

      // Check Bluetooth adapter state
      final btState = await FlutterBluePlus.adapterState.first;
      if (btState != BluetoothAdapterState.on) {
        _btOn = false;
        if (!mounted) return;
        setState(() => _isScanning = false);
        _showBluetoothOffToast();
        return;
      }
      _btOn = true;

      // Request runtime permissions (critical on Android 12+)
      if (!await _checkPermissions()) {
        setState(() => _isScanning = false);
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _errorMessage = 'Unable to start Bluetooth: '
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
      return;
    }

    _scanSub = _ble.scanForGuardianDevices().listen(
      (result) {
        if (mounted) {
          setState(() {
            final existingIdx = _scanResults.indexWhere(
              (r) => r.device.remoteId == result.device.remoteId,
            );
            if (existingIdx >= 0) {
              _scanResults[existingIdx] = result;
            } else {
              _scanResults.add(result);
            }
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _errorMessage = 'Scan failed: '
              '${e.toString().replaceFirst('Exception: ', '')}';
        });
      },
    );

    _scanSub?.onDone(() {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _selectDevice(ScanResult result) async {
    _scanSub?.cancel();
    setState(() {
      _selectedDevice = result;
      _isScanning = false;
      _step = SetupStep.enterWifi;
    });
  }

  Future<void> _provision() async {
    if (_ssidCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill in both SSID and password');
      return;
    }

    setState(() {
      _step = SetupStep.provisioning;
      _provisioningStatus = 'Sending credentials to device...';
      _errorMessage = null;
    });

    if (_selectedDevice == null) {
      setState(() {
        _step = SetupStep.error;
        _errorMessage = 'No device selected. Please scan again.';
      });
      return;
    }

    try {
      final result = await _ble.provisionDevice(
        _selectedDevice!,
        ssid: _ssidCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (mounted) {
        setState(() {
          _provisionedDeviceId = result.deviceId;
          _provisioningStatus = 'Device configured!';
        });
      }

      await _deviceConfig.saveDeviceConfig(
        deviceId: result.deviceId,
        deviceName: result.deviceName,
      );

      try {
        await _firebase.updateUserDeviceId(result.deviceId);
      } catch (_) {}

      setState(() => _step = SetupStep.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = SetupStep.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _retry() => _startScan();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text(
          'Device Setup',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case SetupStep.scan:
        return _buildScanView();
      case SetupStep.enterWifi:
        return _buildWifiEntryView();
      case SetupStep.provisioning:
        return _buildProvisioningView();
      case SetupStep.success:
        return _buildSuccessView();
      case SetupStep.error:
        return _buildErrorView();
    }
  }

  static bool _isGuardianDevice(ScanResult r) {
    final name = r.advertisementData.advName;
    final services = r.advertisementData.serviceUuids;
    final guardianUuid = Guid(BleProvisioningService.serviceUuid);
    return (name.isNotEmpty && name.contains('Guardian_')) ||
           services.any((u) => u == guardianUuid);
  }

  // ─── Scan View ──────────────────────────────────────────────────────────

  Widget _buildScanView() {
    // Split results: Guardian devices first, then everything else
    final guardian = _scanResults.where(_isGuardianDevice).toList();
    final others = _scanResults.where((r) => !_isGuardianDevice(r)).toList();
    final allSorted = [...guardian, ...others];

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: _isScanning
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : const Icon(Icons.bluetooth, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'Scanning for Devices',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isScanning
                    ? 'Make sure your Guardian device is powered on\nand nearby. The LED should be blinking.'
                    : 'Scan complete. ${guardian.length} Guardian device(s),\n${others.length} other device(s) found.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _ErrorBanner(message: _errorMessage!),
          ),
        Expanded(
          child: allSorted.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 48,
                        color: const Color(0xFF9EA8C2).withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isScanning ? 'Searching...' : 'No devices found',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7A99),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isScanning
                            ? 'Listening for BLE advertisements'
                            : 'Ensure Bluetooth and Location are enabled,\nthen press Scan Again',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9EA8C2),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: allSorted.length,
                  itemBuilder: (context, index) {
                    final result = allSorted[index];
                    final isGuardian = _isGuardianDevice(result);
                    return _DeviceCard(
                      name: result.advertisementData.advName.isNotEmpty
                          ? result.advertisementData.advName
                          : result.device.remoteId.toString(),
                      rssi: result.rssi,
                      isGuardian: isGuardian,
                      onTap: () => _selectDevice(result),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: _GuardianSetupButton(
            label: _isScanning ? 'Scanning...' : 'Scan Again',
            loading: _isScanning,
            onPressed: _isScanning ? null : _startScan,
          ),
        ),
      ],
    );
  }

  // ─── WiFi Entry View ────────────────────────────────────────────────────

  Widget _buildWifiEntryView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.wifi, color: Color(0xFF1565C0), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect to WiFi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2340),
                      ),
                    ),
                    Text(
                      'Enter the WiFi network for your device',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SetupTextField(
            controller: _ssidCtrl,
            label: 'WiFi Network Name (SSID)',
            icon: Icons.wifi,
          ),
          const SizedBox(height: 14),
          _SetupTextField(
            controller: _passCtrl,
            label: 'WiFi Password',
            icon: Icons.lock_outline,
            obscureText: _obscurePass,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF6B7A99),
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 28),
          _GuardianSetupButton(
            label: 'Send to Device',
            onPressed: _provision,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _startScan,
              child: const Text(
                'Choose different device',
                style: TextStyle(
                  color: Color(0xFF6B7A99),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Provisioning View ──────────────────────────────────────────────────

  Widget _buildProvisioningView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(
                color: Color(0xFF1565C0),
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Configuring Device',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2340),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _provisioningStatus,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7A99),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'The device will restart automatically\nwhen configuration is complete.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF9EA8C2)),
          ),
        ],
      ),
    );
  }

  // ─── Success View ───────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Color(0xFF43A047), size: 44),
            ),
            const SizedBox(height: 24),
            const Text(
              'Device Configured!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2340),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Device ID',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7A99)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _provisionedDeviceId ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _GuardianSetupButton(
              label: 'Done',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Error View ─────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 44),
            ),
            const SizedBox(height: 24),
            const Text(
              'Setup Failed',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2340),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7A99),
              ),
            ),
            const SizedBox(height: 28),
            _GuardianSetupButton(label: 'Try Again', onPressed: _retry),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF6B7A99),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Device Card ────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final String name;
  final int rssi;
  final bool isGuardian;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.name,
    required this.rssi,
    required this.isGuardian,
    required this.onTap,
  });

  int _rssiBars(int rssi) {
    if (rssi > -50) return 4;
    if (rssi > -65) return 3;
    if (rssi > -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final bars = _rssiBars(rssi);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isGuardian
                        ? const Color(0xFF1565C0).withValues(alpha: 0.1)
                        : const Color(0xFF6B7A99).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isGuardian ? Icons.shield : Icons.bluetooth,
                    color: isGuardian ? const Color(0xFF1565C0) : const Color(0xFF6B7A99),
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
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isGuardian
                                    ? const Color(0xFF1A2340)
                                    : const Color(0xFF6B7A99),
                              ),
                            ),
                          ),
                          if (isGuardian) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'GUARDIAN',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF43A047),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGuardian ? 'Tap to configure' : 'Other device',
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF6B7A99).withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(4, (i) {
                    return Container(
                      width: 4,
                      height: 8 + (i + 1) * 3.0,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: i < bars
                            ? const Color(0xFF1565C0)
                            : const Color(0xFFDDE3F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFF9EA8C2), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ────────────────────────────────────────────────────────

class _SetupTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;

  const _SetupTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A2340),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6B7A99), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF7F9FF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _GuardianSetupButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _GuardianSetupButton({
    required this.label,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFE53935),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}