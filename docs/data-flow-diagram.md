# Data Flow Diagram — GuardianNako IoT Wearable Protection System

## Level 1 DFD

**Figure 3**

*Level 1 Data Flow Diagram of the GuardianNako System*

```mermaid
graph TB
    %% ─── External Entities ───────────────────────────────────────────
    PP["Protected Person<br/>(Wearer)"]
    GC["Guardian/Caregiver<br/>(App User)"]
    EC["Emergency Contacts"]
    GPS["GPS Satellites"]

    %% ─── Data Stores ─────────────────────────────────────────────────
    D1[("D1: Firebase<br/>Realtime Database")]
    D2[("D2: Cloud<br/>Firestore")]
    D3[("D3: ESP32 NVS<br/>(Preferences)")]

    %% ─── Processes ───────────────────────────────────────────────────
    P1("1.0<br/>Collect & Transmit<br/>Sensor Data<br/><i>ESP32</i>")
    P2("2.0<br/>Handle Emergency<br/>Alerts<br/><i>ESP32 + Flutter</i>")
    P3("3.0<br/>Stream Live<br/>Monitoring<br/><i>Flutter</i>")
    P4("4.0<br/>Manage<br/>Geofences<br/><i>Flutter + ESP32</i>")
    P5("5.0<br/>Manage Emergency<br/>Contacts<br/><i>Flutter</i>")
    P6("6.0<br/>Provision Device<br/>via BLE<br/><i>Flutter + ESP32</i>")

    %% ─── Flows: External Entities → Processes ────────────────────────
    PP -->|"Movement / Acceleration"| P1
    PP -->|"SOS Button Press"| P2
    GPS -->|"GPS Coordinates<br/>(NMEA sentences)"| P1
    GC -->|"WiFi Credentials"| P6
    GC -->|"Geofence CRUD<br/>(create, edit, delete, toggle)"| P4
    GC -->|"Contact CRUD<br/>(add, edit, delete)"| P5
    GC -->|"Dismiss Emergency"| P2

    %% ─── Flows: Processes → External Entities ────────────────────────
    P3 -->|"Dashboard: sensor data,<br/>GPS coords, device status"| GC
    P3 -->|"Map: live location marker"| GC
    P3 -->|"Fall Detection: accel bars,<br/>fall status circle"| GC
    P2 -->|"Emergency Alert Banner"| GC
    P4 -->|"Geofence List,<br/>Violation History"| GC
    P5 -->|"Contact List,<br/>Tap-to-Dial"| GC
    P5 -->|"Phone Call (tel: URI)"| EC
    P1 -->|"Status LED<br/>(online/alert)"| PP

    %% ─── Flows: Processes → Data Stores ──────────────────────────────
    P1 -->|"Write sensor data<br/>every 2s"| D1
    P1 -->|"Read/Write<br/>device ID"| D3
    P2 -->|"Write emergency state"| D1
    P2 -->|"Log alert"| D2
    P4 -->|"Write synced geofences"| D1
    P4 -->|"CRUD geofences,<br/>log violations"| D2
    P5 -->|"CRUD contacts"| D2
    P6 -->|"Write WiFi creds,<br/>device ID"| D3
    P6 -->|"Register device ID"| D2

    %% ─── Flows: Data Stores → Processes ──────────────────────────────
    D1 -->|"Stream sensor data"| P3
    D1 -->|"Stream emergency state"| P2
    D1 -->|"Read geofences,<br/>write violations"| P4
    D2 -->|"Read alert history"| P3
    D2 -->|"Read geofence list"| P4
    D2 -->|"Read contact list"| P5
    D3 -->|"Read WiFi creds,<br/>device ID"| P1
```

---

## Level 2 DFDs

### Level 2 — Process 1.0: Collect & Transmit Sensor Data

**Figure 4**

*Level 2 DFD — Process 1.0: Collect & Transmit Sensor Data (ESP32)*

```mermaid
graph TB
    PP["Protected Person<br/>(Wearer)"]
    GPS["GPS Satellites"]
    D1[("D1: Firebase<br/>RTDB")]
    D3[("D3: ESP32 NVS<br/>(Preferences)")]

    P11("1.1<br/>Read Accelerometer<br/>Sensor")
    P12("1.2<br/>Read GPS<br/>Module")
    P13("1.3<br/>Detect Falls")
    P14("1.4<br/>Push Sensor Data<br/>to Firebase")

    PP -->|"Physical Movement"| P11
    GPS -->|"NMEA Sentences"| P12
    D3 -->|"Device ID"| P14

    P11 -->|"ax, ay, az<br/>(g-force)"| P13
    P12 -->|"lat, lng<br/>(if fix updated)"| P14
    P13 -->|"fallDetected: bool<br/>accelMagnitude"| P14
    P13 -->|"Fall detected<br/>(mag > 2.5g)"| P2_trigger("→ 2.0 Handle<br/>Emergency")

    P14 -->|"JSON payload every 2s:<br/>{gps, accelerometer,<br/>fallDetected, timestamp}"| D1
    P14 -->|"Status LED control"| PP
```

---

### Level 2 — Process 2.0: Handle Emergency Alerts

**Figure 5**

*Level 2 DFD — Process 2.0: Handle Emergency Alerts (ESP32 + Flutter)*

```mermaid
graph TB
    PP["Protected Person<br/>(Wearer)"]
    GC["Guardian/Caregiver<br/>(App User)"]
    D1[("D1: Firebase<br/>RTDB")]
    D2[("D2: Cloud<br/>Firestore")]

    P21("2.1<br/>Trigger Emergency<br/><i>ESP32</i>")
    P22("2.2<br/>Stream Emergency<br/>to App<br/><i>Flutter</i>")
    P23("2.3<br/>Dismiss Emergency<br/>& Log Alert<br/><i>Flutter</i>")

    PP -->|"SOS Button Press<br/>(GPIO4, active LOW)"| P21
    P21 -->|"From 1.3:<br/>Fall detected"| P21

    P21 -->|"Write: {active:true,<br/>reason, triggeredAt,<br/>lat, lng}"| D1

    D1 -->|"Stream emergency<br/>state change"| P22
    P22 -->|"Emergency banner +<br/>reason + location"| GC

    GC -->|"Dismiss / Mark as Safe"| P23
    P23 -->|"Write: active=false"| D1
    P23 -->|"Log: {type, message,<br/>deviceId, reason,<br/>timestamp, lat, lng}"| D2
    P23 -->|"Alert logged"| P3_log("→ 3.0 Alert<br/>History UI")

    P23 -->|"Deduplication:<br/>skip duplicate triggeredAt<br/>suppress fall within 3s of SOS"| P23
```

---

### Level 2 — Process 3.0: Stream Live Monitoring

**Figure 6**

*Level 2 DFD — Process 3.0: Stream Live Monitoring (Flutter)*

```mermaid
graph TB
    GC["Guardian/Caregiver<br/>(App User)"]
    D1[("D1: Firebase<br/>RTDB")]
    D2[("D2: Cloud<br/>Firestore")]

    P31("3.1<br/>Render Dashboard<br/><i>HomeScreen Tab 0</i>")
    P32("3.2<br/>Render GPS Map<br/><i>MapScreen Tab 1</i>")
    P33("3.3<br/>Render Fall Detection<br/><i>FallScreen Tab 2</i>")
    P34("3.4<br/>Render Alert History<br/><i>AlertsScreen Tab 3</i>")

    D1 -->|"Stream: /sensors/<br/>{gps, accel,<br/>fallDetected, online}"| P31
    D1 -->|"Stream: /sensors/gps/<br/>{lat, lng}"| P32
    D1 -->|"Stream: /sensors/accelerometer/<br/>{x, y, z}, fallDetected"| P33
    D2 -->|"Query: /users/{uid}/alerts/<br/>ordered by timestamp"| P34

    P31 -->|"Status cards: GPS,<br/>Movement, Fall,<br/>Connectivity"| GC
    P32 -->|"OpenStreetMap +<br/>live marker +<br/>camera follow"| GC
    P33 -->|"Animated fall circle +<br/>X/Y/Z accel bars +<br/>Mark as Safe"| GC
    P34 -->|"Alert summary bar +<br/>chronological list<br/>with type/reason/location"| GC
```

---

### Level 2 — Process 4.0: Manage Geofences

**Figure 7**

*Level 2 DFD — Process 4.0: Manage Geofences (Flutter + ESP32)*

```mermaid
graph TB
    GC["Guardian/Caregiver<br/>(App User)"]
    D1[("D1: Firebase<br/>RTDB")]
    D2[("D2: Cloud<br/>Firestore")]

    P41("4.1<br/>CRUD Geofences<br/><i>Flutter GeofenceScreen</i>")
    P42("4.2<br/>Sync Geofences<br/>to Device<br/><i>Flutter</i>")
    P43("4.3<br/>Check Geofence<br/>Violations<br/><i>ESP32</i>")

    GC -->|"Draw polygon on map,<br/>name, save"| P41
    GC -->|"Edit / Delete / Toggle"| P41

    P41 -->|"Write: /users/{uid}/geofences/{id}/<br/>{name, vertices[], enabled}"| D2
    P41 -->|"Trigger sync"| P42

    P42 -->|"Read enabled geofences"| D2
    P42 -->|"Write array: [{id, name,<br/>lat, lng, radius}]"| D1

    D1 -->|"Read geofence array"| P43
    P43 -->|"Every 30s: Haversine<br/>distance check"| P43
    P43 -->|"Write violation: {geofenceId,<br/>name, type, lat, lng,<br/>distance, timestamp}"| D1

    P41 -->|"Geofence list UI<br/>with toggles"| GC
    D2 -->|"Stream violations"| P41
```

---

### Level 2 — Process 6.0: Provision Device via BLE

**Figure 8**

*Level 2 DFD — Process 6.0: Provision Device via BLE (Flutter + ESP32)*

```mermaid
graph TB
    GC["Guardian/Caregiver<br/>(App User)"]
    D2[("D2: Cloud<br/>Firestore")]
    D3[("D3: ESP32 NVS<br/>(Preferences)")]

    P61("6.1<br/>Scan & Select<br/>Guardian Device<br/><i>Flutter</i>")
    P62("6.2<br/>Connect BLE GATT<br/>& Exchange Data<br/><i>Flutter ↔ ESP32</i>")
    P63("6.3<br/>Save Config &<br/>Register Device<br/><i>Flutter</i>")

    GC -->|"Tap 'Set Up Device',<br/>grant BLE permissions"| P61
    P61 -->|"BLE scan results<br/>(filter Guardian_*)"| GC
    GC -->|"Select device,<br/>enter SSID + password"| P62

    P62 -->|"1. Connect BLE GATT"| P62
    P62 -->|"2. Read device info char<br/>{deviceId, name, version}"| P62
    P62 -->|"3. Subscribe to status notify"| P62
    P62 -->|"4. Write WiFi creds char<br/>{ssid, password}"| P62
    P62 -->|"5. Wait for 'connected' notify"| P62
    P62 -->|"WiFi credentials"| D3

    P62 -->|"Device info +<br/>provisioning status"| GC

    P63 -->|"Save device ID &<br/>name to SharedPrefs"| P63
    P63 -->|"updateUserDeviceId()"| D2
    P63 -->|"Success / Error"| GC
```

---

## Data Dictionary

### D1 — Firebase Realtime Database

| Path | Field | Type | Written By | Read By |
|------|-------|------|------------|---------|
| `/devices/{deviceId}/sensors/gps/lat` | Latitude | `double` | P1.4 (ESP32) | P3.1, P3.2 |
| `/devices/{deviceId}/sensors/gps/lng` | Longitude | `double` | P1.4 (ESP32) | P3.1, P3.2 |
| `/devices/{deviceId}/sensors/accelerometer/x` | Accel X | `float` | P1.4 (ESP32) | P3.1, P3.3 |
| `/devices/{deviceId}/sensors/accelerometer/y` | Accel Y | `float` | P1.4 (ESP32) | P3.1, P3.3 |
| `/devices/{deviceId}/sensors/accelerometer/z` | Accel Z | `float` | P1.4 (ESP32) | P3.1, P3.3 |
| `/devices/{deviceId}/sensors/fallDetected` | Fall flag | `bool` | P1.4 (ESP32) | P3.1, P3.3 |
| `/devices/{deviceId}/sensors/online` | Online flag | `bool` | P1.4 (ESP32) | P3.1 |
| `/devices/{deviceId}/sensors/timestamp` | Server time | `ServerTimestamp` | P1.4 (ESP32) | P3.1 |
| `/devices/{deviceId}/emergency/active` | Emergency active | `bool` | P2.1, P2.3 | P2.2 |
| `/devices/{deviceId}/emergency/reason` | Trigger reason | `string` | P2.1 | P2.2 |
| `/devices/{deviceId}/emergency/triggeredAt` | Trigger time | `ServerTimestamp` | P2.1 | P2.2 |
| `/devices/{deviceId}/emergency/lat` | Emergency lat | `double` | P2.1 | P2.2 |
| `/devices/{deviceId}/emergency/lng` | Emergency lng | `double` | P2.1 | P2.2 |
| `/devices/{deviceId}/geofences/` | Geofence array | `array` | P4.2 | P4.3 |
| `/devices/{deviceId}/geofence_violations/{ts}/` | Violation record | `object` | P4.3 | P4.1 |

### D2 — Cloud Firestore

| Path | Field | Type | Written By | Read By |
|------|-------|------|------------|---------|
| `/users/{uid}/name` | Display name | `string` | Auth flow | P3.1 |
| `/users/{uid}/email` | Email address | `string` | Auth flow | — |
| `/users/{uid}/deviceId` | Linked device | `string` | P6.3 | P3.1 |
| `/users/{uid}/contacts/{id}/name` | Contact name | `string` | P5 | P5 |
| `/users/{uid}/contacts/{id}/phone` | Contact phone | `string` | P5 | P5 |
| `/users/{uid}/contacts/{id}/relationship` | Relationship | `string` | P5 | P5 |
| `/users/{uid}/contacts/{id}/isEmergencyContact` | Emergency flag | `bool` | P5 | P5 |
| `/users/{uid}/geofences/{id}/name` | Geofence name | `string` | P4.1 | P4.1, P4.2 |
| `/users/{uid}/geofences/{id}/vertices` | Polygon vertices | `array<LatLng>` | P4.1 | P4.1, P4.2 |
| `/users/{uid}/geofences/{id}/enabled` | Enabled flag | `bool` | P4.1 | P4.2 |
| `/users/{uid}/alerts/{id}/type` | Alert type | `"sos"\|"fall"\|"emergency"` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/message` | Alert message | `string` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/deviceId` | Source device | `string` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/reason` | Trigger reason | `string` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/timestamp` | Event time | `Timestamp` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/latitude` | Event latitude | `double` | P2.3 | P3.4 |
| `/users/{uid}/alerts/{id}/longitude` | Event longitude | `double` | P2.3 | P3.4 |

### D3 — ESP32 NVS (Preferences)

| Key | Value | Written By | Read By |
|-----|-------|------------|---------|
| `wifi_ssid` | WiFi network name | P6.2 (BLE provisioning) | P1 (ESP32 boot) |
| `wifi_pass` | WiFi password | P6.2 (BLE provisioning) | P1 (ESP32 boot) |
| `device_id` | Auto-generated device ID | P1 (first boot) | P1.4, P6.2 |

---

## Process Summary

| ID | Process | Platform | Frequency | Input | Output |
|----|---------|----------|-----------|-------|--------|
| 1.1 | Read Accelerometer | ESP32 | Every loop | I2C Bus | ax, ay, az |
| 1.2 | Read GPS | ESP32 | Continuous | UART Serial | lat, lng |
| 1.3 | Detect Falls | ESP32 | Every loop | ax, ay, az | fallDetected bool |
| 1.4 | Push Sensor Data | ESP32 | Every 2s | Sensor readings | RTDB JSON |
| 2.1 | Trigger Emergency | ESP32 | On event | SOS button or fall | RTDB emergency |
| 2.2 | Stream Emergency | Flutter | Real-time | RTDB emergency path | UI alert banner |
| 2.3 | Dismiss & Log | Flutter | On user action | Dismiss tap | RTDB clear + Firestore log |
| 3.1 | Render Dashboard | Flutter | Real-time | RTDB /sensors/ | Status cards |
| 3.2 | Render GPS Map | Flutter | Real-time | RTDB /sensors/gps/ | Map marker |
| 3.3 | Render Fall Detection | Flutter | Real-time | RTDB /sensors/accelerometer/ | Accel bars + circle |
| 3.4 | Render Alert History | Flutter | Real-time | Firestore /alerts/ | Alert list |
| 4.1 | CRUD Geofences | Flutter | On user action | Polygon vertices | Firestore + UI |
| 4.2 | Sync Geofences | Flutter | On save/toggle | Firestore geofences | RTDB array |
| 4.3 | Check Violations | ESP32 | Every 30s | RTDB geofences | RTDB violations |
| 5.0 | Manage Contacts | Flutter | On user action | Contact form data | Firestore + UI |
| 6.1 | Scan & Select Device | Flutter | On setup | BLE advertisements | Device list |
| 6.2 | Connect & Exchange | Flutter ↔ ESP32 | Per provisioning | BLE GATT | WiFi creds + status |
| 6.3 | Save & Register | Flutter | Post-provisioning | Device info | SharedPrefs + Firestore |
