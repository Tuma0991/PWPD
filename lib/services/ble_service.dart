import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProvisioningService {
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String deviceInfoCharUuid = '4fafc202-1fb5-459e-8fcc-c5c9c331914b';
  static const String wifiCredsCharUuid = '4fafc203-1fb5-459e-8fcc-c5c9c331914b';
  static const String provStatusCharUuid = '4fafc204-1fb5-459e-8fcc-c5c9c331914b';

  final Guid _serviceGuid = Guid(serviceUuid);

  Stream<ScanResult> scanForGuardianDevices({Duration timeout = const Duration(seconds: 15)}) async* {
    await FlutterBluePlus.startScan(timeout: timeout);

    await for (final results in FlutterBluePlus.scanResults) {
      for (final result in results) {
        final name = result.advertisementData.advName;
        if (name.contains('Guardian_')) {
          yield result;
        }
      }
    }
  }

  Future<({String deviceId, String deviceName})> provisionDevice(
    ScanResult scanResult, {
    required String ssid,
    required String password,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) async {
    final device = scanResult.device;
    final deviceName = scanResult.advertisementData.advName;

    try {
      await device.connect(timeout: connectionTimeout);
      await device.discoverServices();

      BluetoothService? service;
      for (final s in device.servicesList) {
        if (s.serviceUuid == _serviceGuid) {
          service = s;
          break;
        }
      }

      if (service == null) {
        throw Exception('Guardian provisioning service not found on device');
      }

      BluetoothCharacteristic? deviceInfoChar;
      BluetoothCharacteristic? wifiCredsChar;
      BluetoothCharacteristic? provStatusChar;

      for (final c in service.characteristics) {
        final uuid = c.characteristicUuid.toString();
        if (uuid == deviceInfoCharUuid) {
          deviceInfoChar = c;
        } else if (uuid == wifiCredsCharUuid) {
          wifiCredsChar = c;
        } else if (uuid == provStatusCharUuid) {
          provStatusChar = c;
        }
      }

      if (deviceInfoChar == null || wifiCredsChar == null) {
        throw Exception('Required BLE characteristics not found');
      }

      final deviceInfoRaw = await deviceInfoChar.read();
      final deviceInfo = jsonDecode(utf8.decode(deviceInfoRaw)) as Map<String, dynamic>;
      final deviceId = deviceInfo['deviceId'] as String? ?? '';

      final credsJson = jsonEncode({'ssid': ssid, 'password': password});
      await wifiCredsChar.write(utf8.encode(credsJson), withoutResponse: false);

      if (provStatusChar != null) {
        await provStatusChar.setNotifyValue(true);
        final completer = Completer<String>();

        final subscription = provStatusChar.onValueReceived.listen((value) {
          try {
            final status = jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
            if (status['status'] == 'connected') {
              completer.complete(status['message'] as String? ?? 'Device connected');
            } else if (status['status'] == 'failed') {
              completer.completeError(Exception(status['message'] ?? 'Provisioning failed'));
            }
          } catch (_) {}
        });

        try {
          await completer.future.timeout(const Duration(seconds: 20));
        } on TimeoutException {
          // ESP32 likely already rebooted, which is expected
        } finally {
          await subscription.cancel();
        }
      }

      // Give the ESP32 time to reboot
      await Future.delayed(const Duration(seconds: 1));

      try {
        await device.disconnect();
      } catch (_) {}

      return (deviceId: deviceId, deviceName: deviceName);
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}

      if (e is Exception) rethrow;
      throw Exception('Provisioning failed: $e');
    }
  }
}
