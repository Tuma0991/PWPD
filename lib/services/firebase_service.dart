// lib/services/firebase_service.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../models/device_data.dart';
import '../models/contact_model.dart';
import '../models/geofence_model.dart';
import '../models/device_settings_model.dart';
import '../models/paired_device.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;

  String? _lastSyncedEmail;
  String? _lastSyncedName;

  FirebaseService._internal() {
    // Keep the Firestore `name`/`email` copy in sync with Auth, including
    // changes that happen outside a sign-in — e.g. the email being verified
    // after `verifyBeforeUpdateEmail`, or profile edits made elsewhere.
    _auth.userChanges().listen((user) {
      if (user == null) {
        _lastSyncedEmail = null;
        _lastSyncedName = null;
        return;
      }
      final email = user.email ?? '';
      final name = user.displayName ?? '';
      if (email == _lastSyncedEmail && name == _lastSyncedName) return;
      _lastSyncedEmail = email;
      _lastSyncedName = name;
      _syncProfileToFirestore(user.uid, name: name, email: email);
    });
  }

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseDatabase get _rtdb => FirebaseDatabase.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  bool _googleInitialized = false;

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
    await _ensureUserDocument(cred.user!, name: name, email: email);
    return cred;
  }

  /// Signs the user in with their Google account. Returns null if the user
  /// cancels the Google account picker, otherwise the resulting credential.
  Future<UserCredential?> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize();
      _googleInitialized = true;
    }

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await google.authenticate();
    } on GoogleSignInException catch (e) {
      // On Android, some configuration errors (e.g. a missing SHA-1) surface
      // as `canceled`, so log every failure to make it visible in the console.
      debugPrint('Google sign-in failed: ${e.code} — ${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Google sign-in did not return an ID token.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await _auth.signInWithCredential(credential);
    await _ensureUserDocument(
      userCredential.user!,
      name: googleUser.displayName,
      email: googleUser.email,
    );
    return userCredential;
  }

  Future<void> _ensureUserDocument(
    User user, {
    String? name,
    String? email,
  }) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'name': name ?? user.displayName ?? '',
        'email': email ?? user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Warning: Failed to create user document: $e');
    }
  }

  /// Mirrors the Auth profile (name + email) into the user's Firestore doc.
  /// Called from the `userChanges` listener; a `merge` write leaves `createdAt`
  /// and any other fields untouched.
  Future<void> _syncProfileToFirestore(
    String uid, {
    required String name,
    required String email,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'name': name,
        'email': email,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Warning: Failed to sync user profile: $e');
    }
  }

  Future<void> signOut() async => await _auth.signOut();

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ─── ACCOUNT PROFILE ──────────────────────────────────────────────────────

  /// Updates the user's display name in both Auth and their Firestore doc.
  Future<void> updateProfileName(String name) async {
    final user = currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    await _firestore.collection('users').doc(user.uid).update({'name': name});
  }

  /// Re-authenticates the current user with their password. Required before
  /// sensitive changes (email/password) because Firebase rejects them without
  /// a recent login.
  Future<void> reauthenticate(String password) async {
    final user = currentUser;
    if (user == null) return;
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'No email address on this account.',
      );
    }
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(credential);
  }

  /// Starts an email change by sending a verification link to [newEmail].
  /// The address is only updated after the user clicks that link, so the
  /// Firestore `email` copy is left unchanged here.
  Future<void> requestEmailChange(String newEmail) async {
    final user = currentUser;
    if (user == null) return;
    await user.verifyBeforeUpdateEmail(newEmail);
  }

  Future<void> updatePassword(String newPassword) async {
    final user = currentUser;
    if (user == null) return;
    await user.updatePassword(newPassword);
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
      final data =
          Map<String, dynamic>.from(event.snapshot.value as Map? ?? {});
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
        .map((snap) => snap.docs
            .map((d) => ContactModel.fromMap(d.id, d.data()))
            .toList());
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
        .map((snap) => snap.docs
            .map((d) => GeofenceModel.fromMap(d.id, d.data()))
            .toList());
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
      final data =
          Map<String, dynamic>.from(event.snapshot.value as Map? ?? {});
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

    await _firestore.collection('users').doc(userId).collection('alerts').add({
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

    await _rtdb.ref('devices/$deviceId/geofences').set(geofenceList);
  }

  // ─── DEVICE SETTINGS (wearer profile) ───────────────────────────────────

  /// Live wearer profile (name + photo) for a device. Empty when not set.
  Stream<DeviceSettingsModel> listenToDeviceSettings(String deviceId) {
    final user = currentUser;
    if (user == null || deviceId.isEmpty) {
      return Stream.value(const DeviceSettingsModel());
    }
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

  // ─── DEVICES (paired device list) ─────────────────────────────────────────

  /// Streams the user's paired devices (one doc per device under
  /// `users/{uid}/devices`), ordered by when they were added.
  Stream<List<PairedDevice>> listenToDevices() {
    final user = currentUser;
    if (user == null) return Stream.value(const []);
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .orderBy('addedAt')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PairedDevice.fromMap(d.id, d.data()))
            .toList());
  }

  /// Reads the current paired devices once (used for FCM token fan-out).
  Future<List<PairedDevice>> getDevices() async {
    final user = currentUser;
    if (user == null) return const [];
    final snap = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .get();
    return snap.docs.map((d) => PairedDevice.fromMap(d.id, d.data())).toList();
  }

  /// Adds (or claims) a device for the current user and marks it as owned.
  Future<void> addDevice(String deviceId, {required String deviceName}) async {
    final user = currentUser;
    if (user == null || deviceId.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .set({
      'deviceId': deviceId,
      'deviceName': deviceName,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await setDeviceOwner(deviceId);
  }

  Future<void> renameDevice(String deviceId, String deviceName) async {
    final user = currentUser;
    if (user == null || deviceId.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .update({'deviceName': deviceName});
  }

  /// Removes a device from the user's list, cleans up their FCM token, and
  /// clears ownership if this user owned it.
  Future<void> removeDevice(String deviceId) async {
    final user = currentUser;
    if (user == null || deviceId.isEmpty) return;

    await removeFcmToken(deviceId);

    final ownerSnap = await _rtdb.ref('devices/$deviceId/owner').get();
    if (ownerSnap.value == user.uid) {
      await _rtdb.ref('devices/$deviceId/owner').remove();
    }

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .delete();
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

    await _rtdb.ref('devices/$deviceId/fcmTokens/$userId').set({
      'token': token,
      'platform': 'android',
      'registeredAt': ServerValue.timestamp,
    });
  }

  /// Registers this phone's FCM token under every paired device, so the user
  /// receives push notifications for all of them (not just the active one).
  Future<void> registerFcmTokenForAllDevices() async {
    final devices = await getDevices();
    for (final d in devices) {
      await registerFcmToken(d.deviceId);
    }
  }

  /// Removes this phone's FCM token from every paired device (logout).
  Future<void> removeFcmTokenForAllDevices() async {
    final devices = await getDevices();
    for (final d in devices) {
      await removeFcmToken(d.deviceId);
    }
  }

  /// Mark this user as the owner of a device. The Cloud Function reads this
  /// to find the owner's emergency contacts when an alert fires.
  Future<void> setDeviceOwner(String deviceId) async {
    final userId = currentUser?.uid;
    if (userId == null || deviceId.isEmpty) return;

    // Set the owner and register this phone's token. Tokens are no longer
    // wiped here so that re-pairing or multiple phones for the same user
    // don't clobber each other's registrations.
    await _rtdb.ref('devices/$deviceId/owner').set(userId);
    await registerFcmToken(deviceId);
  }

  /// Remove the FCM token for this user from a device (on logout / device
  /// unpair).
  Future<void> removeFcmToken(String deviceId) async {
    final userId = currentUser?.uid;
    if (userId == null || deviceId.isEmpty) return;
    await _rtdb.ref('devices/$deviceId/fcmTokens/$userId').remove();
  }

  /// Removes a user's FCM token from the given devices. Used on logout, where
  /// `currentUser` is already null but the uid + device ids were captured
  /// while signed in.
  Future<void> removeFcmTokensForDevices(
      String userId, List<String> deviceIds) async {
    if (userId.isEmpty) return;
    for (final id in deviceIds) {
      if (id.isEmpty) continue;
      await _rtdb.ref('devices/$id/fcmTokens/$userId').remove();
    }
  }
}
