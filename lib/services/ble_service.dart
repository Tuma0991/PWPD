import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProvisioningService {
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String deviceInfoCharUuid = '4fafc202-1fb5-459e-8fcc-c5c9c331914b';
  static const String wifiCredsCharUuid = '4fafc203-1fb5-459e-8fcc-c5c9c331914b';
  static const String provStatusCharUuid = '4fafc204-1fb5-459e-8fcc-c5c9c331914b';

  final Guid _serviceGuid = Guid(serviceUuid);

  Stream<ScanResult> scanForGuardianDevices({Duration timeout = const Duration(seconds: 15)}) async* {
    // Do an unfiltered scan. Android's withServices filter is unreliable with
    // 128-bit UUIDs. We scan for everything and match in Dart.
    await FlutterBluePlus.startScan(timeout: timeout);

    await for (final results in FlutterBluePlus.scanResults) {
      for (final result in results) {
        yield result;
      }
    }
  }

  Future<({String deviceId, String deviceName})> provisionDevice(
    ScanResult scanResult, {
    required String ssid,
    required String password,
    Duration connectionTimeout = const Duration(seconds: 10),
  }) async {
    final device = scanResult.device;
    final deviceName = scanResult.advertisementData.advName;

    try {
      // Retry connection up to 3 times. Android BLE stacks sometimes fail
      // the first connection attempt with freshly discovered devices.
      Exception? lastError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await device.connect(timeout: connectionTimeout);
          lastError = null;
          break;
        } on Exception catch (e) {
          lastError = e;
          debugPrint('[BLE] connect attempt $attempt/3 failed: $e');
          if (attempt < 3) {
            // Give the peripheral and Android BLE stack time to recover
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      if (lastError != null) throw lastError;

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

      // Set up notification listener BEFORE writing credentials.
      // The ESP32 reboots ~1.5s after receiving the write, so we need to
      // be listening before the write, not after.
      StreamSubscription? statusSub;
      final completer = Completer<String>();

      if (provStatusChar != null) {
        await provStatusChar.setNotifyValue(true);
        statusSub = provStatusChar.onValueReceived.listen((value) {
          try {
            final status = jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
            if (status['status'] == 'connected') {
              if (!completer.isCompleted) {
                completer.complete(status['message'] as String? ?? 'Device configured');
              }
            } else if (status['status'] == 'failed') {
              if (!completer.isCompleted) {
                completer.completeError(
                  Exception(status['message'] ?? 'Provisioning failed'));
              }
            }
          } catch (_) {}
        });
      }

      final credsJson = jsonEncode({'ssid': ssid, 'password': password});
      await wifiCredsChar.write(utf8.encode(credsJson), withoutResponse: false);

      if (provStatusChar != null) {
        try {
          await completer.future.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          // ESP32 reboots after saving creds — timeout is normal.
        } finally {
          await statusSub?.cancel();
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
