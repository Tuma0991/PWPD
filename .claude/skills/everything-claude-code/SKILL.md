---
name: project-conventions
description: Development conventions and patterns for the Guardian IoT Wearable Protection Device project — Flutter/Dart, ESP32 firmware, and Firebase backend.
---

# Guardian IoT Project Conventions

Project-specific development patterns and conventions for the Guardian IoT Wearable Protection Device.

## Tech Stack

- **Mobile**: Flutter/Dart (Material 3, `flutter_map`, `firebase_*` packages)
- **Backend**: Firebase (Auth, Firestore, Realtime Database)
- **Firmware**: ESP32-S3 with Arduino C++ (MPU6050 + GT-U8 GPS)
- **Primary Language**: Dart

## When to Use This Skill

Activate this skill when:
- Making changes to this repository
- Adding new Flutter screens, widgets, or services
- Modifying ESP32 firmware
- Writing tests that match project conventions
- Creating commits with proper message format

## Commit Conventions

### Commit Style: Conventional Commits

### Prefixes Used

- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation changes
- `refactor` — code restructuring
- `test` — adding or updating tests
- `chore` — tooling, dependencies, config

### Message Guidelines

- Keep first line concise and descriptive
- Use imperative mood ("Add feature" not "Added feature")

*Commit message example*

```text
feat: add fall detection alert to dashboard
```

*Commit message example*

```text
fix: resolve RTDB stream disconnect on app background
```

*Commit message example*

```text
docs: update ESP32 wiring diagram in README
```

## Architecture

### Data Flow

```
ESP32 (WiFi) → Firebase RTDB (/devices/{deviceId}/sensors) → Stream listener → Flutter UI
ESP32 (WiFi) → Firebase RTDB (/devices/{deviceId}/emergency) → Stream listener → Flutter UI
Flutter App  ↔ Firebase Firestore (/users/{uid}/contacts, geofences, alerts)
Flutter App  ↔ Firebase Auth (email/password)
```

### Key Patterns

- **Singleton service**: `FirebaseService()` accessed as a singleton throughout the app
- **Auth gating**: `_AuthGate` widget listens to `authStateChanges` stream
- **RTDB streams**: `listenToDeviceData(deviceId)` and `listenToEmergencyAlert(deviceId)`
- **Firestore CRUD**: Contacts, geofences, and alert history via Firestore

### Project Structure

```
lib/
├── main.dart              # App entry, _AuthGate, BottomNavigationBar
├── theme.dart             # Material 3 theme, deep blue primary
├── models/                # DeviceData, ContactModel, GeofenceModel
├── services/              # firebase_service.dart (singleton)
├── screens/               # Home, Map, Sensors, Alerts, Geofences, Contacts
└── widgets/               # Reusable widgets (if any)
esp32_firmware/
└── guardian_firmware/     # Arduino C++ project for ESP32
```

## Code Style

### Language: Dart

### Naming Conventions

| Element | Convention |
|---------|------------|
| Files | snake_case |
| Classes | PascalCase |
| Functions/Methods | camelCase |
| Variables | camelCase |
| Constants | camelCase (Dart convention) or SCREAMING_SNAKE_CASE for C++ |

### Import Style

Use package imports for Firebase/third-party, relative for project files:

```dart
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../models/device_data.dart';
```

## Testing

### Test Types

- **Widget tests**: `flutter test` for individual widgets
- **Unit tests**: Pure Dart functions and model logic
- **Integration tests**: Firebase service integration

### Coverage

Aim for meaningful test coverage of critical paths (fall detection alerts, auth flow, data parsing).

## Error Handling

```dart
try {
  await FirebaseService().signIn(email, password);
} catch (e) {
  // Log and surface user-friendly message
  debugPrint('Auth error: $e');
  showError('Sign in failed. Check your credentials.');
}
```

## Best Practices

### Do

- Use conventional commit format (`feat:`, `fix:`, etc.)
- Follow dart convention naming (snake_case files, PascalCase classes)
- Keep `FirebaseService` as the single Firebase entry point
- Use streams for real-time data, not polling
- Test Firebase operations with emulators when possible

### Don't

- Don't write vague commit messages
- Don't skip tests for critical safety features (fall detection, emergency alerts)
- Don't hardcode device IDs or Firebase credentials
- Don't add new Firebase dependencies without going through `FirebaseService`

---

*Adapted for the Guardian IoT Wearable Protection Device project.*
