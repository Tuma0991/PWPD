# Guardian System Architecture

## Overview

**Guardian** (branded as "GuardianNako") is an IoT Wearable Protection Device system consisting of three major components:

1. **ESP32 Firmware** — wearable hardware with MPU6050 accelerometer, NEO-6M GPS, SOS button, and BLE provisioning
2. **Firebase Backend** — real-time sensor data (RTDB) + persistent user data (Firestore) + authentication
3. **Flutter Mobile App** — live monitoring dashboard, GPS map, fall detection, geofencing, emergency contacts, and BLE device setup

---

## High-Level Architecture

```
┌─────────────────────┐     WiFi/HTTPS      ┌──────────────────────┐     SDK/Streams     ┌──────────────────────┐
│    ESP32 Firmware   │ ──────────────────> │   Firebase Backend   │ <────────────────── │    Flutter Mobile App │
│                     │                     │                      │                     │                      │
│  • MPU6050 (accel)  │   RTDB writes       │  Realtime Database   │   RTDB streams      │  • Dashboard         │
│  • NEO-6M GPS       │   (every 2s)        │                      │                     │  • Live GPS Map      │
│  • SOS Button       │                     │  • /devices/{id}/    │   Firestore CRUD    │  • Fall Detection    │
│  • BLE Server       │ <─ ─ ─ ─ ─ ─ ─ ─ ─ │    sensors           │                     │  • Alert History     │
│  • Geofence Check   │   BLE provisioning  │    emergency         │   Auth state        │  • Geofence Manager  │
│  • Fall Detection   │   (WiFi creds)      │    geofences         │                     │  • Contacts Manager  │
│                     │                     │                      │                     │  • BLE Device Setup  │
│                     │                     │  Firestore           │                     │                      │
└─────────────────────┘                     │                      │                     └──────────────────────┘
        │                                   │  • /users/{uid}/     │                              │
        │                                   │    contacts          │                              │
   Sensors:                                 │    geofences         │                         BLE Provisioning
   Accel + GPS                              │    alerts            │                     (WiFi credentials to ESP32)
                                            │                      │
                                            │  Firebase Auth       │
                                            │  (email/password)    │
                                            └──────────────────────┘
```

---

## Component Architecture

### 1. ESP32 Firmware

**File:** `esp32_firmware/guardian_firmware/guardian_firmware.ino`

The ESP32 is the wearable device worn by the protected person. It reads sensor data and pushes it to Firebase every 2 seconds.

```
┌──────────────────────────────────────────────────┐
│                  ESP32 Board                      │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐   │
│  │ MPU6050  │  │ NEO-6M  │  │  SOS Button   │   │
│  │ Accel/Gyro│  │   GPS   │  │  (GPIO 4)     │   │
│  │ I2C:22,21│  │ UART2   │  │  Active LOW   │   │
│  └────┬─────┘  └────┬─────┘  └──────┬────────┘   │
│       │             │               │             │
│       ▼             ▼               ▼             │
│  ┌───────────────────────────────────────────┐    │
│  │              Main Loop                     │    │
│  │                                            │    │
│  │  • Read MPU6050 → ax, ay, az (g-force)    │    │
│  │  • Feed GPS → lat, lng                    │    │
│  │  • Detect falls (mag > 2.5g threshold)    │    │
│  │  • Detect SOS button press (debounced)    │    │
│  │  • Push sensor data every 2s              │    │
│  │  • Check geofences every 30s              │    │
│  │  • Poll emergency clear flag              │    │
│  └──────────────────┬────────────────────────┘    │
│                     │                              │
│  ┌──────────────────▼────────────────────────┐    │
│  │         Connectivity Manager              │    │
│  │                                            │    │
│  │  WiFi (shared radio with BLE):            │    │
│  │  • Connect to provisioned network         │    │
│  │  • Firebase_ESP_Client (mobizt)           │    │
│  │                                            │    │
│  │  BLE Server (unprovisioned mode):         │    │
│  │  • Device Info characteristic (read)      │    │
│  │  • WiFi Credentials characteristic (write)│    │
│  │  • Provisioning Status characteristic     │    │
│  │    (notify)                                │    │
│  └───────────────────────────────────────────┘    │
│                                                   │
│  Storage: Preferences (NVS)                       │
│  • WiFi SSID & password                          │
│  • Device ID (auto-generated from MAC)            │
└──────────────────────────────────────────────────┘
```

**Key algorithms:**
- **Fall Detection:** Calculates acceleration magnitude `sqrt(x² + y² + z²)`. A fall is triggered when magnitude exceeds 2.5g, respecting a 5s cooldown and 3s SOS-suppression window.
- **Geofence Checking:** Implements the Haversine formula for distance calculation. Checks all synced geofences every 30s, tracking enter/exit state transitions.
- **BLE Provisioning:** Advertises as "Guardian_XXXX" with a 128-bit custom service UUID. Provides device metadata, accepts WiFi credentials, and notifies connection status before reboot.

---

### 2. Firebase Backend

The backend uses a dual-database strategy: **Realtime Database** for live streaming sensor data, and **Firestore** for persistent structured user data.

#### Realtime Database (RTDB) — High-Frequency Sensor Data

```
/devices/{deviceId}/
├── sensors/                          # Written by ESP32 every 2s
│   ├── gps/
│   │   ├── lat: double
│   │   └── lng: double
│   ├── accelerometer/
│   │   ├── x: float
│   │   ├── y: float
│   │   └── z: float
│   ├── fallDetected: bool
│   ├── online: bool
│   └── timestamp: ServerTimestamp
├── emergency/                        # Written by ESP32 on event
│   ├── active: bool                  # Written by Flutter to clear
│   ├── reason: string
│   ├── triggeredAt: ServerTimestamp
│   ├── lat: double
│   └── lng: double
├── geofences/                        # Written by Flutter, read by ESP32
│   └── [ { id, name, lat, lng, radius } ]
└── geofence_violations/              # Written by ESP32
    └── {timestamp}/
        ├── geofenceId: string
        ├── name: string
        ├── type: "entered" | "exited"
        ├── lat: double
        ├── lng: double
        ├── distance: double
        └── timestamp: ServerTimestamp
```

#### Firestore — Persistent Structured Data

```
/users/{uid}/
├── name: string
├── email: string
├── deviceId: string
├── createdAt: Timestamp
├── contacts/{contactId}/
│   ├── name: string
│   ├── phone: string
│   ├── relationship: string
│   └── isEmergencyContact: bool
├── geofences/{geofenceId}/
│   ├── userId: string
│   ├── name: string
│   ├── vertices: [ { lat, lng }, ... ]
│   ├── enabled: bool
│   ├── createdAt: Timestamp
│   └── updatedAt: Timestamp
├── alerts/{alertId}/
│   ├── type: "sos" | "fall" | "emergency"
│   ├── message: string
│   ├── deviceId: string
│   ├── reason: string
│   ├── timestamp: Timestamp
│   ├── latitude: double
│   └── longitude: double
└── geofence_violations/{violationId}/
    ├── geofenceId: string
    ├── name: string
    ├── type: "entered" | "exited"
    ├── lat, lng, distance: double
    └── timestamp: Timestamp
```

#### Auth

Firebase Auth with email/password. On registration, a user document is created at `Firestore /users/{uid}` with `name`, `email`, and `createdAt`.

---

### 3. Flutter Mobile App

**Entry Point:** `lib/main.dart` → `_AuthGate` widget gates between `AuthScreen` and `HomeScreen` based on `authStateChanges` stream.

#### Service Layer

```
┌─────────────────────────────────────────────────────┐
│                 FirebaseService                       │
│                 (Singleton)                           │
│                                                       │
│  Auth:                                                │
│  ├── signIn(email, password)                          │
│  ├── register(email, password, name)                  │
│  ├── signOut()                                        │
│  ├── resetPassword(email)                             │
│  ├── authStateChanges → Stream<User?>                 │
│  └── updateUserDeviceId(deviceId)                     │
│                                                       │
│  RTDB (live sensor streams):                          │
│  ├── listenToDeviceData(deviceId) → Stream<DeviceData>│
│  ├── listenToEmergencyAlert(deviceId) → Stream<Map>   │
│  └── clearEmergency(deviceId)                         │
│                                                       │
│  Firestore — Alerts:                                  │
│  ├── getAlertHistory(userId) → Stream<QuerySnapshot>  │
│  └── logAlert(userId, alertData)                      │
│                                                       │
│  Firestore — Contacts:                                │
│  ├── getContacts(userId) → Stream<QuerySnapshot>      │
│  ├── addContact / updateContact / deleteContact       │
│                                                       │
│  Firestore — Geofences:                               │
│  ├── getGeofences(userId) → Stream<QuerySnapshot>     │
│  ├── addGeofence / updateGeofence / deleteGeofence    │
│  ├── syncGeofencesToDevice(deviceId, geofences)       │
│  ├── getGeofenceViolations(userId) → Stream           │
│  └── logGeofenceViolation(userId, data)               │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              BleProvisioningService                   │
│                                                       │
│  ├── scanForGuardianDevices() → List<ScanResult>      │
│  └── provisionDevice(scanResult, ssid, pwd)           │
│        → { deviceId, deviceName }                     │
│                                                       │
│  Custom UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b   │
│  Chars: Device Info (read) / WiFi Creds (write)       │
│         / Provisioning Status (notify)                │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              DeviceConfigService                      │
│                                                       │
│  SharedPreferences keys:                              │
│  ├── configured_device_id                            │
│  ├── configured_device_name                          │
│  ├── last_configured_timestamp                       │
│  └── isDeviceConfigured → bool                       │
└─────────────────────────────────────────────────────┘
```

#### Screen Hierarchy

```
GuardianApp (MaterialApp)
│
├── _AuthGate (StreamBuilder<User?>)
│   ├── [Loading] → Splash spinner
│   ├── [Authenticated] → HomeScreen
│   └── [Unauthenticated] → AuthScreen
│
├── AuthScreen
│   ├── Login tab (email, password, remember me, forgot password)
│   └── Register tab (name, email, password, confirm)
│
├── HomeScreen (BottomNavigationBar — 6 tabs via IndexedStack)
│   ├── Tab 0: _DashboardTab (inline widget)
│   │   ├── Welcome banner + device status
│   │   ├── Emergency alert banner (RTDB stream)
│   │   └── Status cards: GPS, Movement, Fall, Connectivity
│   ├── Tab 1: MapScreen
│   │   ├── flutter_map with OpenStreetMap tiles
│   │   ├── Live GPS marker (auto-follow)
│   │   └── Device info card
│   ├── Tab 2: FallDetectionScreen
│   │   ├── Fall status circle (animated gradient)
│   │   ├── Accelerometer X/Y/Z bars
│   │   └── Mark as Safe button
│   ├── Tab 3: AlertsScreen
│   │   ├── Alert summary bar (counts)
│   │   └── Alert history list (Firestore)
│   ├── Tab 4: GeofenceScreen
│   │   ├── Map with polygon drawing
│   │   ├── Vertex management
│   │   └── Geofence list with toggles
│   ├── Tab 5: ContactsScreen
│   │   ├── Emergency contacts section
│   │   ├── Other contacts section
│   │   └── Add/Edit bottom sheet
│   └── Logout button
│
└── DeviceSetupScreen
    ├── Step 1: BLE Scan
    ├── Step 2: WiFi Credentials Entry
    ├── Step 3: Provisioning (progress)
    ├── Step 4: Success
    └── Step 5: Error (retry)
```

#### Data Models

```
DeviceData                          ContactModel
├── latitude: double?               ├── id: String
├── longitude: double?              ├── name: String
├── accelX: double                  ├── phone: String
├── accelY: double                  ├── relationship: String
├── accelZ: double                  └── isEmergencyContact: bool
├── fallDetected: bool
├── timestamp: int (epoch ms)       GeofenceModel
├── > deviceOnline: bool            ├── id: String
│   (timestamp within 10s)          ├── userId: String
├── > accelMagnitude: double        ├── name: String
│   sqrt(x²+y²+z²)                  ├── vertices: List<LatLng>
└── > lastSeenLabel: String         ├── enabled: bool
    (relative time)                 ├── createdAt: DateTime
                                    └── updatedAt: DateTime
```

---

## Key Data Flows

### 1. Real-Time Sensor Data Flow

```
ESP32 loop (every 2s)
  │
  ├── Read MPU6050 → ax, ay, az
  ├── Feed GPS → lat, lng (if updated)
  ├── Detect falls (accel mag > 2.5g)
  │
  └── pushSensorData()
        │
        ▼
  Firebase RTDB: /devices/{deviceId}/sensors/
    { gps: {lat, lng}, accelerometer: {x, y, z}, fallDetected, timestamp }
        │
        ▼ (Stream via firebase_database onValue)
  FirebaseService.listenToDeviceData(deviceId)
        │
        ▼ DeviceData.fromMap()
  StreamBuilder<DeviceData>
        │
        ├── Dashboard: status cards, GPS coords, movement bars
        ├── MapScreen: device location marker + camera follow
        └── FallDetectionScreen: accelerometer visualization
```

### 2. Emergency Alert Flow

```
ESP32
  │
  ├── SOS Button (GPIO 4, active LOW)
  │     └── triggerEmergency("SOS button pressed")
  │
  └── Fall Detection (accel mag > 2.5g)
        └── triggerEmergency("Fall detected by accelerometer")
              │
              ▼
  Firebase RTDB: /devices/{deviceId}/emergency/
    { active: true, reason, triggeredAt, lat, lng }
              │
              ▼ (Stream)
  FirebaseService.listenToEmergencyAlert(deviceId)
              │
              ├── Dashboard: red emergency banner + Dismiss button
              │     └── Dismiss → clearEmergency() → RTDB active: false
              │
              ├── FallDetectionScreen: red status circle + Mark as Safe
              │
              └── AlertsScreen (dedup + log to Firestore):
                    │
                    ├── Skip first snapshot (existing state)
                    ├── Detect NEW emergencies (state comparison)
                    ├── Dedup by triggeredAt timestamp
                    ├── Suppress SOS-jolt false falls (3s window)
                    │
                    └── logAlert() → Firestore /users/{uid}/alerts/
                          { type, message, deviceId, reason, timestamp, lat, lng }
                              │
                              ▼
                        getAlertHistory() stream → UI alert list
```

### 3. Geofence Flow

```
Flutter GeofenceScreen
  │
  ├── User draws polygon on map (tap to place vertices)
  ├── Save: addGeofence(userId, geofenceData)
  │     │
  │     └── Firestore: /users/{uid}/geofences/{id}
  │           { name, vertices, enabled, createdAt }
  │
  └── Sync: syncGeofencesToDevice(deviceId, enabledGeofences)
        │
        ▼
  Firebase RTDB: /devices/{deviceId}/geofences/
    [ { id, name, lat, lng, radius }, ... ]
        │
        ▼ (ESP32 reads)
  ESP32: fetchGeofences()
    │
    └── Every 30s: checkGeofences()
          ├── For each geofence: calculateDistance() (Haversine)
          ├── Compare to lastGeofenceStatus[]
          ├── Detect entry/exit transitions
          └── On violation: logGeofenceViolation()
                │
                ▼
          Firebase RTDB: /devices/{deviceId}/geofence_violations/{ts}
            { geofenceId, name, type, lat, lng, distance, timestamp }
```

### 4. Device Provisioning Flow (BLE)

```
Flutter DeviceSetupScreen
  │
  ├── Check Bluetooth state + request Android permissions
  ├── scanForGuardianDevices()
  │     └── Filter BLE devices by name "Guardian_" or service UUID
  ├── User selects device + enters WiFi SSID/password
  │
  └── provisionDevice(scanResult, ssid, password)
        │
        ├── Connect to ESP32 BLE GATT
        ├── Read device info characteristic → { deviceId, name, version }
        ├── Subscribe to status notifications (BEFORE writing credentials)
        ├── Write WiFi credentials { ssid, password } as JSON
        ├── Wait for "connected" status notification (ESP32 reboots ~1.5s)
        └── Disconnect
              │
              ├── Save to SharedPreferences (DeviceConfigService)
              └── Save to Firebase: updateUserDeviceId(deviceId)

ESP32 BLE Server
  │
  ├── Advertise as "Guardian_XXXX" with service UUID
  ├── Expose characteristics:
  │     ├── Device Info (read): JSON { deviceId, firmware, wifiStatus }
  │     ├── WiFi Credentials (write): JSON { ssid, password }
  │     └── Status (notify): "connected" | "error"
  ├── On credentials write:
  │     ├── Save to NVS (Preferences)
  │     ├── Send "connected" notification
  │     └── Set pendingRestart flag
  └── loop() detects pendingRestart → ESP.restart()
        └── Reboot → connect WiFi → connect Firebase
```

### 5. Authentication Flow

```
User enters credentials in AuthScreen
  │
  ├── Register: FirebaseService.register(email, password, name)
  │     ├── FirebaseAuth.createUserWithEmailAndPassword()
  │     ├── user.updateDisplayName(name)
  │     └── Firestore: /users/{uid}/
  │           { name, email, createdAt }
  │
  └── Login: FirebaseService.signIn(email, password)
        └── FirebaseAuth.signInWithEmailAndPassword()
              │
              ▼
  authStateChanges stream emits User object
        │
        ▼
  _AuthGate (StreamBuilder) rebuilds → HomeScreen
```

---

## Technical Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Hardware** | ESP32 | Microcontroller with WiFi + BLE |
| **Sensors** | MPU6050, NEO-6M GPS | Accelerometer/gyroscope + GPS positioning |
| **Firmware** | Arduino C++ | Sensor reading, fall detection, Firebase client |
| **BLE Provisioning** | ESP32 BLE Server + flutter_blue_plus | WiFi credential transfer |
| **Real-time Data** | Firebase Realtime Database | Live sensor streams (2s interval) |
| **Persistent Data** | Cloud Firestore | User data, contacts, geofences, alert history |
| **Authentication** | Firebase Auth | Email/password authentication |
| **Mobile App** | Flutter 3.x (Dart) | Cross-platform mobile app |
| **Maps** | flutter_map + OpenStreetMap | Free tile-based mapping (no API key) |
| **State Management** | StreamBuilder + setState | Firebase streams drive UI updates |
| **Local Storage** | SharedPreferences | Device config, remember-me email |
| **Phone Calls** | url_launcher (tel: URI) | Emergency contact dialing |

---

## Package Dependencies

### Firebase Stack
- `firebase_core` — Firebase initialization
- `firebase_auth` — Email/password authentication
- `firebase_database` — Realtime Database streams
- `cloud_firestore` — Firestore CRUD operations

### Maps & Location
- `flutter_map` + `flutter_map_cancellable_tile_provider` — OpenStreetMap rendering
- `latlong2` — Coordinate data types
- `geolocator` — Device GPS (declared, not yet wired)

### BLE
- `flutter_blue_plus` — BLE scanning and GATT operations

### UI & UX
- `intl` — Date/time formatting
- `shimmer`, `lottie`, `flutter_svg` — Animation/icon libraries (declared, assets pending)

### Utilities
- `url_launcher` — Dialer integration for emergency calls
- `shared_preferences` — Local key-value storage
- `permission_handler` — Android runtime permissions for BLE

---

## Cross-Cutting Concerns

### Offline Detection

Device online status is determined by timestamp staleness: if the last sensor update is older than 10 seconds (5 missed 2-second update intervals), the device is considered offline. No separate heartbeat mechanism is used.

### Emergency Deduplication

Multiple layers prevent duplicate emergency handling:
- **ESP32:** Guards against re-triggering an already-active emergency
- **Flutter AlertsScreen:** Tracks `triggeredAt` timestamps to skip already-logged events; suppresses fall alerts within 3 seconds of an SOS press (the button jolt can produce a false accelerometer spike)

### Radios

The ESP32 uses a single radio for both WiFi and BLE. When in provisioning mode (no WiFi credentials), WiFi is disabled with `WiFi.mode(WIFI_OFF)` to free the radio for BLE advertising. After provisioning, BLE stops and WiFi connects.

### Security

- Firebase Auth secures all data access via Security Rules
- RTDB and Firestore paths are scoped by authenticated user ID and device ID
- WiFi credentials are transferred over BLE (local, short-range) during provisioning only
