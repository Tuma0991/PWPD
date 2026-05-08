# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

IoT Wearable Protection Device ("Guardian") — a Flutter mobile app paired with ESP32 firmware and a Firebase backend. The ESP32 (with MPU6050 accelerometer + NEO-6M GPS) pushes sensor data to Firebase Realtime Database every 2 seconds. The Flutter app listens via RTDB streams for live updates and uses Firestore for persistent data (contacts, geofences, alert history).

## Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run the app on a connected device/emulator
flutter analyze          # Static analysis (lints from flutter_lints)
flutter test             # Run tests (currently one stale widget test)
flutter build apk        # Build Android APK
```

## Architecture

### Data flow

```
ESP32 (WiFi) → Firebase RTDB (/devices/{deviceId}/sensors) → Stream listener → Flutter UI
ESP32 (WiFi) → Firebase RTDB (/devices/{deviceId}/emergency) → Stream listener → Flutter UI
Flutter App  ↔ Firebase Firestore (/users/{uid}/contacts, geofences, alerts)
Flutter App  ↔ Firebase Auth (email/password)
```

### FirebaseService (singleton)

`lib/services/firebase_service.dart` — the single entry point for all Firebase operations. Accessed as `FirebaseService()` anywhere in the app (always returns the same instance). Covers:
- **Auth**: `signIn`, `register`, `signOut`, `resetPassword`, `authStateChanges` stream
- **RTDB**: `listenToDeviceData(deviceId)` → `Stream<DeviceData>`, `listenToEmergencyAlert(deviceId)`, `clearEmergency(deviceId)`
- **Firestore**: CRUD for contacts, geofences, geofence violations; alert history with ordering

### Auth gating

`lib/main.dart` uses an `_AuthGate` widget that listens to `FirebaseService().authStateChanges` — shows `HomeScreen` when authenticated, `AuthScreen` when not, and a loading spinner while Firebase initializes.

### Screens and navigation

`HomeScreen` provides a `BottomNavigationBar` with 6 tabs:

| Tab | File | Key dependency |
|-----|------|---------------|
| Dashboard | `home_screen.dart` (`_DashboardTab`) | `listenToDeviceData`, `listenToEmergencyAlert` |
| Map | `map_screen.dart` | `flutter_map` (OpenStreetMap tiles), device GPS stream |
| Sensors | `fall_detection_screen.dart` | Accelerometer data + fall status |
| Alerts | `alerts_screen.dart` | Firestore alert history |
| Geofences | `geofence_screen.dart` | Firestore geofence CRUD, RTDB sync |
| Contacts | `contacts_screen.dart` | Firestore contacts CRUD, `url_launcher` for calling |

### Models

- `DeviceData` — parsed from RTDB sensor snapshots. Online/offline detection via timestamp staleness (10s threshold), computed `accelMagnitude`, `lastSeenLabel`, `copyWith`.
- `ContactModel` — Firestore-backed with `id`, `name`, `phone`, `relationship`, `isEmergencyContact`.
- `GeofenceModel` — Firestore-backed with `latitude`, `longitude`, `radiusMeters`, `enabled`, etc.

### Theme

`lib/theme.dart` — Material 3, `ColorScheme.fromSeed` with deep blue primary (`#1565C0`), Nunito font family. `AppTheme.primary` / `AppTheme.danger` etc. are used directly throughout the app (not only via `Theme.of(context)`).

### Maps

Uses `flutter_map` with OpenStreetMap tiles (no API key required). NOT Google Maps — the README references Google Maps setup but the actual code uses OpenStreetMap via `flutter_map` + `flutter_map_cancellable_tile_provider`.

## ESP32 Firmware

Located in `esp32_firmware/guardian_firmware/`. Arduino C++ project targeting ESP32. Key config: WiFi credentials, Firebase host/auth, `DEVICE_ID`, `FALL_ACCEL_THRESHOLD` (2.5g default), `UPDATE_INTERVAL_MS` (2000ms default). Requires libraries: Firebase ESP32 Client (mobizt), TinyGPS++, MPU6050 (Electronic Cats), ArduinoJson. Configuration template at `ESP32_CONFIG_TEMPLATE.h`.
