// lib/services/firebase_service.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_data.dart';
import '../models/contact_model.dart';
import '../models/geofence_model.dart';
import '../models/device_settings_model.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseDatabase get _rtdb => FirebaseDatabase.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ─── AUTH ────────────────────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> register(
      String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.updateDisplayName(name);
    
    // Create user document with error handling
    try {
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Warning: Failed to create user document: $e');
    }
    return cred;
  }

  Future<void> signOut() async => await _auth.signOut();

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> updateUserDeviceId(String deviceId) async {
    final user = currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'deviceId': deviceId,
    });
  }

  Future<String?> getUserDeviceId() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['deviceId'] as String?;
  }

  // ─── REAL-TIME DEVICE DATA (ESP32 → Firebase RTDB) ───────────────────────

  /// ESP32 pushes data here:
  /// /devices/{deviceId}/sensors → { gps, accelerometer, fallDetected, timestamp }
  Stream<DeviceData> listenToDeviceData(String deviceId) {
    final ref = _rtdb.ref('devices/$deviceId/sensors');
    return ref.onValue.map((event) {
      final data = Map<String, dynamic>.from(
          event.snapshot.value as Map? ?? {});
      return DeviceData.fromMap(data);
    });
  }

  /// Listen to emergency alerts with reason
  Stream<Map<String, dynamic>> listenToEmergencyAlert(String deviceId) {
    final ref = _rtdb.ref('devices/$deviceId/emergency');
    return ref.onValue.map((event) {
      return Map<String, dynamic>.from(event.snapshot.value as Map? ?? {});
    });
  }

  /// Acknowledge / clear emergency
  Future<void> clearEmergency(String deviceId) async {
    await _rtdb.ref('devices/$deviceId/emergency').set({
      'active': false,
      'clearedAt': ServerValue.timestamp,
    });
  }

  /// Ask the device to turn GPS on and report its position now. The firmware
  /// polls /devices/{deviceId}/commands every ~30 s (active) / 60 s (resting),
  /// so the update arrives shortly after, not instantly.
  Future<void> requestDeviceLocation(String deviceId) async {
    await _rtdb.ref('devices/$deviceId/commands/locateNow').set(true);
  }

  // ─── ALERT HISTORY (Firestore) ───────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getAlertHistory(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> logAlert(String userId, Map<String, dynamic> alertData) async {
    // Use caller-provided timestamp if present, otherwise server timestamp
    if (!alertData.containsKey('timestamp')) {
      alertData['timestamp'] = FieldValue.serverTimestamp();
    }
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .add(alertData);
  }

  // ─── CONTACTS ────────────────────────────────────────────────────────────

  Stream<List<ContactModel>> getContacts(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('contacts')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ContactModel.fromMap(d.id, d.data())).toList());
  }

  Future<void> addContact(String userId, ContactModel contact) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('contacts')
        .add(contact.toMap());
  }

  Future<void> updateContact(
      String userId, String contactId, ContactModel contact) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('contacts')
        .doc(contactId)
        .update(contact.toMap());
  }

  Future<void> deleteContact(String userId, String contactId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('contacts')
        .doc(contactId)
        .delete();
  }

  // ─── GEOFENCES ─────────────────────────────────────────────────────────────

  /// Get all geofences for a user
  Stream<List<GeofenceModel>> getGeofences(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('geofences')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => GeofenceModel.fromMap(d.id, d.data())).toList());
  }

  /// Add a new geofence
  Future<String> addGeofence(String userId, GeofenceModel geofence) async {
    final docRef = await _firestore
        .collection('users')
        .doc(userId)
        .collection('geofences')
        .add(geofence.toMap());
    return docRef.id;
  }

  /// Update an existing geofence
  Future<void> updateGeofence(
      String userId, String geofenceId, GeofenceModel geofence) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('geofences')
        .doc(geofenceId)
        .update({
      ...geofence.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a geofence
  Future<void> deleteGeofence(String userId, String geofenceId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('geofences')
        .doc(geofenceId)
        .delete();
  }

  /// Get geofence violations for a user (Firestore — historical)
  Stream<List<Map<String, dynamic>>> getGeofenceViolations(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('geofence_violations')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Listen to real-time geofence violations from the ESP32 via RTDB.
  /// The ESP32 writes violations to /devices/{deviceId}/geofence_violations/{ts}.
  Stream<Map<String, dynamic>> listenToGeofenceViolationsRTDB(String deviceId) {
    final ref = _rtdb.ref('devices/$deviceId/geofence_violations');
    return ref.onChildAdded.map((event) {
      final data = Map<String, dynamic>.from(
          event.snapshot.value as Map? ?? {});
      data['_rtdbKey'] = event.snapshot.key;
      return data;
    });
  }

  /// Log a geofence violation received from ESP32 into Firestore so it
  /// appears in the AlertsScreen history and can be queried later.
  Future<void> logGeofenceViolationToAlerts(
      String userId, Map<String, dynamic> violationData) async {
    final type = violationData['type'] ?? 'exited';
    final name = violationData['name'] ?? 'Unknown zone';
    final lat = violationData['lat'];
    final lng = violationData['lng'];

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .add({
      'type': 'geofence_$type',
      'message': 'Device $type geofence "$name"',
      'deviceId': violationData['deviceId'] ?? '',
      'latitude': lat,
      'longitude': lng,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Log a geofence violation (Firestore)
  Future<void> logGeofenceViolation(
      String userId, Map<String, dynamic> violationData) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('geofence_violations')
        .add({
      ...violationData,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Sync geofences to ESP32 device (polygon vertices)
  Future<void> syncGeofencesToDevice(
      String deviceId, List<GeofenceModel> geofences) async {
    final geofenceList = geofences
        .where((g) => g.enabled)
        .map((g) => {
              'id': g.id,
              'name': g.name,
              'vertices': g.vertices
                  .map((v) => {'lat': v.latitude, 'lng': v.longitude})
                  .toList(),
            })
        .toList();

    await _rtdb
        .ref('devices/$deviceId/geofences')
        .set(geofenceList);
  }

  // ─── DEVICE SETTINGS (wearer profile) ───────────────────────────────────

  /// Live wearer profile (name + photo) for a device. Empty when not set.
  Stream<DeviceSettingsModel> listenToDeviceSettings(String deviceId) {
    final user = currentUser;
    if (user == null) return Stream.value(const DeviceSettingsModel());
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .map((snap) => snap.exists
            ? DeviceSettingsModel.fromMap(snap.data() ?? {})
            : const DeviceSettingsModel());
  }

  Future<void> updateDeviceSettings(
    String deviceId, {
    String? name,
    String? photoBase64,
  }) async {
    final user = currentUser;
    if (user == null || deviceId.isEmpty) return;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (photoBase64 != null) updates['photoBase64'] = photoBase64;
    if (updates.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set(updates, SetOptions(merge: true));
  }

  // ─── FCM PUSH NOTIFICATIONS ──────────────────────────────────────────────

  /// Register this device (phone) to receive push notifications for the
  /// given ESP32 device. Stored in RTDB so the Cloud Function can look up
  /// tokens when a geofence violation occurs.
  Future<void> registerFcmToken(String deviceId) async {
    final userId = currentUser?.uid;
    if (userId == null || deviceId.isEmpty) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await _rtdb
        .ref('devices/$deviceId/fcmTokens/$userId')
        .set({
      'token': token,
      'platform': 'android',
      'registeredAt': ServerValue.timestamp,
    });
  }

  /// Mark this user as the owner of a device. The Cloud Function reads this
  /// to find the owner's emergency contacts when an alert fires.
  /// Also clears old FCM tokens so previous owners stop receiving push
  /// notifications.
  Future<void> setDeviceOwner(String deviceId) async {
    final userId = currentUser?.uid;
    if (userId == null || deviceId.isEmpty) return;

    // Clear all previous FCM tokens so old owners aren't notified
    await _rtdb.ref('devices/$deviceId/fcmTokens').remove();
    // Set new owner
    await _rtdb.ref('devices/$deviceId/owner').set(userId);
    // Then register the new owner's FCM token
    await registerFcmToken(deviceId);
  }

  /// Remove the FCM token for this user from a device (on logout / device
  /// unpair).
  Future<void> removeFcmToken(String deviceId) async {
    final userId = currentUser?.uid;
    if (userId == null || deviceId.isEmpty) return;
    await _rtdb.ref('devices/$deviceId/fcmTokens/$userId').remove();
  }
}
