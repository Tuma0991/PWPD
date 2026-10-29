import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's active device selection locally.
///
/// The list of paired devices lives in Firestore (`users/{uid}/devices`); this
/// service only remembers which one the UI is currently showing. Legacy
/// single-device keys are kept solely for a one-time migration on upgrade.
class DeviceConfigService {
  static const _keyActiveDeviceId = 'active_device_id';
  static const _keyLegacyDeviceId = 'configured_device_id';
  static const _keyLegacyDeviceName = 'configured_device_name';
  static const _keyLegacyLastConfigured = 'last_configured_timestamp';

  Future<String?> getActiveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveDeviceId);
  }

  Future<void> setActiveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveDeviceId, deviceId);
  }

  Future<void> clearActiveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActiveDeviceId);
  }

  /// One-time backfill for installs that predate multi-device support: if no
  /// active device is set but the old single-device keys exist, return them and
  /// clear the legacy keys so the migration only runs once.
  Future<({String deviceId, String deviceName})?> migrateLegacyDevice() async {
    final prefs = await SharedPreferences.getInstance();

    final active = prefs.getString(_keyActiveDeviceId);
    if (active != null && active.isNotEmpty) return null;

    final id = prefs.getString(_keyLegacyDeviceId);
    if (id == null || id.isEmpty) return null;

    final name = prefs.getString(_keyLegacyDeviceName) ?? '';
    await prefs.remove(_keyLegacyDeviceId);
    await prefs.remove(_keyLegacyDeviceName);
    await prefs.remove(_keyLegacyLastConfigured);

    return (deviceId: id, deviceName: name);
  }
}
