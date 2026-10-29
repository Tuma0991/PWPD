// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/firebase_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

/// Global key for showing SnackBars from FCM foreground handler.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// External setter so HomeScreen can tell us which tab to switch to when
/// a notification is tapped.
void Function(int index)? _navigateToTab;

void setNotificationTapHandler(void Function(int index)? handler) {
  _navigateToTab = handler;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ── FCM setup ──────────────────────────────────────────────────────────
  final messaging = FirebaseMessaging.instance;

  // Android notification channel (must be created before any notification)
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Handle notification tap while app is in background (not terminated)
  FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

  // Handle notification that launched the app from terminated state
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    // Will be handled after HomeScreen builds — stash for later
    _pendingInitialMessage = initialMessage;
  }

  // Foreground: show a SnackBar (RTDB listener handles this in MapScreen,
  // but FCM foreground handler is the safety net when the user is on another tab)
  FirebaseMessaging.onMessage.listen(_onForegroundMessage);

  // FCM token refresh — re-register across all paired devices
  messaging.onTokenRefresh.listen((_) {
    final firebase = FirebaseService();
    if (firebase.currentUser != null) {
      firebase.registerFcmTokenForAllDevices();
    }
  });

  runApp(const GuardianApp());
}

RemoteMessage? _pendingInitialMessage;

void _onMessageOpenedApp(RemoteMessage message) {
  _handleNotificationNavigation(message.data);
}

void _onForegroundMessage(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;

  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.notifications_active, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notification.body ?? 'Geofence alert',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFE53935),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

void _handleNotificationNavigation(Map<String, dynamic> data) {
  // Navigate to the Geofence tab (index 4) when a geofence notification
  // is tapped.
  if (data['type'] is String) {
    _navigateToTab?.call(4);
  }
}

/// If the app was launched from a terminated state via a notification tap,
/// apply the pending navigation after the HomeScreen is built.
void consumePendingInitialMessage() {
  final msg = _pendingInitialMessage;
  if (msg != null) {
    _pendingInitialMessage = null;
    _handleNotificationNavigation(msg.data);
  }
}

class GuardianApp extends StatelessWidget {
  const GuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.theme,
      home: const _AuthGate(),
    );
  }
}

/// Routes to HomeScreen if user is already logged in, otherwise AuthScreen
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final firebase = FirebaseService();
    return StreamBuilder(
      stream: firebase.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'lib/images/Logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Guardian',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: AppTheme.primary),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return const HomeScreen();
        }

        return const AuthScreen();
      },
    );
  }
}
