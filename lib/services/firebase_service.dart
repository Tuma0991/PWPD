// lib/services/firebase_service.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_data.dart';
import '../models/contact_model.dart';

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
        'deviceId': 'esp32_device_1',
      });
    } catch (e) {
      // Log error but don't crash - user is already created in Auth
      print('Warning: Failed to create user document: $e');
    }
    return cred;
  }

  Future<void> signOut() async => await _auth.signOut();

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
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

  // ─── ALERT HISTORY (Firestore) ───────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getAlertHistory(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> logAlert(String userId, Map<String, dynamic> alertData) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('alerts')
        .add({
      ...alertData,
      'timestamp': FieldValue.serverTimestamp(),
    });
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
}
