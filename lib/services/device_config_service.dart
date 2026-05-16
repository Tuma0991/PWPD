import 'package:shared_preferences/shared_preferences.dart';

class DeviceConfigService {
  static const _keyDeviceId = 'configured_device_id';
  static const _keyDeviceName = 'configured_device_name';
  static const _keyLastConfigured = 'last_configured_timestamp';

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceId);
  }

  Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceName);
  }

  Future<void> saveDeviceConfig({
    required String deviceId,
    required String deviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceId, deviceId);
    await prefs.setString(_keyDeviceName, deviceName);
    await prefs.setInt(_keyLastConfigured, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clearDeviceConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceId);
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyLastConfigured);
  }

  Future<bool> get isDeviceConfigured async {
    final id = await getDeviceId();
    return id != null && id.isNotEmpty;
  }
}
