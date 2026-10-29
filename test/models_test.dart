import 'package:flutter_test/flutter_test.dart';
import 'package:personal_wearable_protection_device/models/contact_model.dart';
import 'package:personal_wearable_protection_device/models/device_data.dart';

void main() {
  group('DeviceData', () {
    test('fromMap parses nested GPS and accelerometer data', () {
      final data = DeviceData.fromMap({
        'gps': {'lat': 10.3157, 'lng': 123.8854},
        'accelerometer': {'x': 0.1, 'y': 0.2, 'z': 9.8},
        'fallDetected': true,
        'timestamp': 1234567890,
      });

      expect(data.latitude, 10.3157);
      expect(data.longitude, 123.8854);
      expect(data.accelX, 0.1);
      expect(data.accelY, 0.2);
      expect(data.accelZ, 9.8);
      expect(data.fallDetected, isTrue);
      expect(data.timestamp, 1234567890);
    });

    test('fromMap defaults missing fields', () {
      final data = DeviceData.fromMap({});

      expect(data.latitude, 0.0);
      expect(data.longitude, 0.0);
      expect(data.accelX, 0.0);
      expect(data.accelY, 0.0);
      expect(data.accelZ, 0.0);
      expect(data.fallDetected, isFalse);
      expect(data.timestamp, 0);
    });

    test('accelMagnitude sums squared components', () {
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 1,
        accelY: 2,
        accelZ: 3,
        fallDetected: false,
        timestamp: 0,
      );

      expect(data.accelMagnitude, 14.0);
    });

    test('deviceOnline is true for a fresh timestamp', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        fallDetected: false,
        timestamp: now,
      );

      expect(data.deviceOnline, isTrue);
      expect(data.isOnlineStale, isFalse);
    });

    test('deviceOnline is false for a stale timestamp', () {
      // Fallback threshold is 15 min; 16 min is definitely stale.
      final stale = DateTime.now().millisecondsSinceEpoch - 16 * 60 * 1000;
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        fallDetected: false,
        timestamp: stale,
      );

      expect(data.deviceOnline, isFalse);
      expect(data.isOnlineStale, isTrue);
    });

    test('offline threshold scales with the reported heartbeat interval', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        fallDetected: false,
        timestamp: now,
        hbIntervalS: 120,
      );

      // 2.5 x the active 120 s heartbeat = 300 s
      expect(data.onlineStaleThresholdSeconds, 300);
    });

    test('deviceOnline is false once the heartbeat interval is exceeded', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stale = now - 301 * 1000; // just past the 300 s active threshold
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        fallDetected: false,
        timestamp: stale,
        hbIntervalS: 120,
      );

      expect(data.deviceOnline, isFalse);
      expect(data.isOnlineStale, isTrue);
    });

    test('deviceOnline is false when timestamp is 0', () {
      final data = DeviceData(
        latitude: 0,
        longitude: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 0,
        fallDetected: false,
        timestamp: 0,
      );

      expect(data.deviceOnline, isFalse);
      expect(data.isOnlineStale, isTrue);
    });

    test('copyWith updates only the specified fields', () {
      final original = DeviceData(
        latitude: 1,
        longitude: 2,
        accelX: 3,
        accelY: 4,
        accelZ: 5,
        fallDetected: false,
        timestamp: 100,
      );

      final updated = original.copyWith(latitude: 99);

      expect(updated.latitude, 99);
      expect(updated.longitude, original.longitude);
      expect(updated.accelX, original.accelX);
      expect(updated.timestamp, original.timestamp);
    });
  });

  group('ContactModel', () {
    test('fromMap parses all fields', () {
      final contact = ContactModel.fromMap('abc', {
        'name': 'Alice',
        'phone': '09171234567',
        'relationship': 'Mother',
        'carrier': 'Globe (PH)',
        'isEmergencyContact': true,
      });

      expect(contact.id, 'abc');
      expect(contact.name, 'Alice');
      expect(contact.phone, '09171234567');
      expect(contact.relationship, 'Mother');
      expect(contact.carrier, 'Globe (PH)');
      expect(contact.isEmergencyContact, isTrue);
    });

    test('toMap round-trips through fromMap', () {
      final contact = ContactModel(
        id: 'abc',
        name: 'Alice',
        phone: '09171234567',
        relationship: 'Mother',
        carrier: 'Globe (PH)',
        isEmergencyContact: true,
      );

      final restored = ContactModel.fromMap('abc', contact.toMap());

      expect(restored.name, contact.name);
      expect(restored.phone, contact.phone);
      expect(restored.relationship, contact.relationship);
      expect(restored.carrier, contact.carrier);
      expect(restored.isEmergencyContact, contact.isEmergencyContact);
    });

    test('copyWith updates only the specified fields', () {
      final contact = ContactModel(
        id: 'abc',
        name: 'Alice',
        phone: '09171234567',
        relationship: 'Mother',
        carrier: 'Globe (PH)',
        isEmergencyContact: true,
      );

      final updated = contact.copyWith(isEmergencyContact: false);

      expect(updated.isEmergencyContact, isFalse);
      expect(updated.name, contact.name);
      expect(updated.phone, contact.phone);
    });
  });
}
