# Chapter 3 — Methodology

## 3.1 System Development Methodology

The development of the GuardianNako IoT Wearable Protection System followed an **iterative and incremental development approach**. The project was broken into four distinct phases: analysis, design, development, and testing. Each phase produced concrete deliverables — diagrams, prototypes, working firmware modules, and tested application features — that were reviewed and refined before proceeding.

This approach was chosen because the system spans three distinct platforms (ESP32 firmware, Flutter mobile application, and Firebase cloud backend) that must integrate seamlessly. Iterative development allowed each platform to be built and validated independently before integration, reducing the risk of late-stage compatibility issues.

---

## 3.2 System Analysis

### 3.2.1 Problem Statement

Caregivers of elderly individuals, young children, and persons with medical conditions face constant uncertainty about their loved one's safety when they are apart. Existing solutions are either expensive subscription-based services, require the wearer to carry a smartphone, or lack real-time emergency capabilities. There is a need for an affordable, dedicated wearable device that provides continuous location tracking, automatic fall detection, and instant emergency alerting — all accessible through a simple mobile application.

### 3.2.2 Proposed System

The GuardianNako system consists of three integrated components:

1. **ESP32 Wearable Device** — A small, low-cost hardware device worn by the protected person. It contains an MPU6050 accelerometer for motion sensing, a GT-U8 GPS module for location tracking, a physical SOS button for manual emergency activation, and a status LED for visual feedback. The device connects to the internet via WiFi and transmits sensor data every two seconds.

2. **Flutter Mobile Application** — A cross-platform mobile app used by the guardian or parent. It displays a live dashboard with real-time sensor readings, a GPS map showing the wearer's location, fall detection status, emergency alert banners, geofence management tools, and an emergency contact list with tap-to-dial functionality.

3. **Firebase Cloud Backend** — Google's Firebase platform serves as the cloud layer. Firebase Authentication handles user sign-in. The Firebase Realtime Database (RTDB) carries live, transient data streams (sensor readings, emergency state, geofence violations). Cloud Firestore stores persistent, structured data (user profiles, contacts, geofence definitions, alert history).

### 3.2.3 Requirements Gathering

Requirements were gathered through analysis of the problem domain and identification of the core monitoring, safety, and communication needs between a protected person and their guardian. The functional requirements were organized into ten use cases grouped into four categories: monitoring, managing, emergency, and device-side operations. Two supporting use cases handle background data streaming and persistent storage.

### 3.2.4 Functional Requirements (Use Cases)

The system is defined by ten use cases across four functional groups, plus two supporting use cases that run behind the scenes.

**Monitoring Group**

| Use Case | Actor | Description |
|----------|-------|-------------|
| UC01 — View Dashboard | Guardian | The guardian opens the app and sees live status cards for GPS coordinates, movement data, fall detection status, and device connectivity. An emergency banner appears at the top when an alert is active, with an inline dismiss button. All data updates in real time without manual refresh. |
| UC02 — View Live GPS Map | Guardian | The guardian views an OpenStreetMap showing the wearer's current location as a live marker. The map supports auto-follow mode that keeps the marker centered as the wearer moves. |
| UC03 — Monitor Fall Detection | Guardian | The guardian sees three animated bars representing real-time X, Y, and Z accelerometer readings from the wearable device, plus a fall status indicator circle (green for normal, red for fall detected). A "Mark as Safe" button clears an active fall alert. |
| UC06 — View Alert History | Guardian | The guardian navigates to the Alerts tab and sees a summary bar with alert counts by type (SOS, fall, geofence), followed by a chronological list of past alerts. Each entry shows the alert type with an icon, the reason or message, the date and time, and the GPS location at the time of the event. |

**Managing Group**

| Use Case | Actor | Description |
|----------|-------|-------------|
| UC04 — Manage Geofences | Guardian | The guardian creates safe zones by drawing polygons on a map, assigns each a name (e.g., "School," "Home"), and toggles them on or off. The system automatically syncs enabled geofences to the wearable device, which enforces them every 30 seconds using Haversine distance calculations. Violations are logged and streamed to the guardian's app in real time. |
| UC05 — Manage Contacts | Guardian | The guardian adds, edits, and deletes emergency contacts with names, phone numbers, relationships, and an emergency priority flag. During an active emergency, the guardian can tap any contact to initiate a phone call directly from the app. |

**Emergency Group**

| Use Case | Actor | Description |
|----------|-------|-------------|
| UC07 — Trigger SOS | Wearer | The protected person presses and holds the physical SOS button on the wearable device. The ESP32 detects the press (with debounce), reads the current GPS location, and immediately sends an emergency alert with the reason "SOS button pressed," the current location, and the time. The guardian's app displays a red banner with the reason and location. |

**Device-Side Group**

| Use Case | Actor | Description |
|----------|-------|-------------|
| UC08 — Generate Sensor Data | Wearer | As the protected person moves throughout their day, the wearable device continuously reads the accelerometer (X, Y, Z axes) and GPS module. It calculates movement magnitude, checks whether it exceeds the fall threshold of 2.5g, and sends all sensor readings — motion data, GPS coordinates, fall detection flag, and a timestamp — to the cloud every two seconds. |

**Supporting Use Cases (Background)**

| Use Case | Included By | Description |
|----------|-------------|-------------|
| UC09 — Stream Sensor Data | UC01, UC02, UC03, UC07, UC08 | The live data channel that carries sensor readings and emergency state from the wearable device to the guardian's app in real time via Firebase Realtime Database. The ESP32 writes data every two seconds; the app receives updates instantly through RTDB stream listeners. |
| UC10 — Store Persistent Data | UC04, UC05, UC06 | The persistent storage layer that keeps user profiles, contacts, geofence definitions, and alert history durably saved in Cloud Firestore. Data is organized as document collections under each user account and is available whenever the app needs it. |

### 3.2.5 Non-Functional Requirements

- **Real-time responsiveness**: Sensor data and emergency alerts must reach the guardian's app within two seconds of being transmitted by the device.
- **Reliability**: The emergency alert mechanism must function even when GPS has no fix, falling back to the last known location.
- **Usability**: The guardian's app must present complex sensor data in an intuitive, glanceable format suitable for non-technical users.
- **Affordability**: The system must use off-the-shelf, low-cost hardware components (ESP32 development board, MPU6050, GT-U8 GPS) and open-source software libraries with no recurring API fees (OpenStreetMap instead of Google Maps).
- **Offline awareness**: The app must clearly indicate when the device goes offline (no update received for 10 seconds).
- **Deduplication**: The system must prevent duplicate emergency alerts from the same triggering event.

---

## 3.3 System Design

### 3.3.1 Conceptual Design — Context Diagram (Figure 1)

The context diagram establishes the system boundary and identifies all external entities that interact with the GuardianNako system. The system — comprising the ESP32 wearable device and the Flutter mobile app — sits at the center and communicates with five external entities:

- **Protected Person (Wearer)**: The person being monitored. Their physical movement and SOS button presses flow into the system as inputs. The system provides visual feedback to the wearer through a status LED that indicates power, connectivity, and active alert state.

- **Guardian / Parent (App User)**: The caregiver who uses the mobile app. The guardian sends configuration data into the system — WiFi credentials for device setup, geofence definitions (polygon zones with names and enabled/disabled status), and emergency contact details. The guardian receives live monitoring outputs from the system: a dashboard with sensor readings and device status, a GPS map with the wearer's live location, emergency alert banners with location and reason, and a chronological alert history.

- **GPS Satellites**: Provide raw GPS coordinate data (NMEA sentences) to the wearable device's GPS receiver module. This is a one-way input flow — the system receives coordinates but does not transmit back to the satellites.

- **Firebase Cloud**: Serves as both a data sink and a data source. The system pushes sensor readings and emergency state to Firebase. Firebase streams real-time data back to the mobile app and serves persisted records on demand.

- **Emergency Contacts**: People the guardian designates as emergency contacts. The system outputs phone calls to these contacts via the device's tap-to-dial feature. Contacts do not directly interact with the system — they are recipients of communication initiated by the guardian.

### 3.3.2 Use Case Design — Use Case Diagram (Figure 2)

The use case diagram organizes the ten functional requirements into a visual model showing which actors interact with which parts of the system. The system boundary encloses four functional groups:

- **Monitoring group** (UC01, UC02, UC03, UC06): Associated with the Guardian actor. Covers all real-time viewing of the wearer's status — dashboard, GPS map, fall detection, and alert history.

- **Managing group** (UC04, UC05): Associated with the Guardian actor for geofence management and with both the Guardian and Emergency Contacts actors for contact management. Covers all configuration activities.

- **Emergency group** (UC07): Associated solely with the Wearer actor. The only use case where the protected person actively interacts with the system — pressing the physical SOS button.

- **Device-side group** (UC08): Associated solely with the Wearer actor. A passive use case — the wearer's normal movement generates the sensor data that powers the entire monitoring system.

Two supporting use cases (UC09 Stream Sensor Data, UC10 Store Persistent Data) operate in the background and are included by the main use cases. UC09 is included by all monitoring and emergency use cases. UC10 is included by the managing and alert history use cases.

### 3.3.3 Data Flow Design — Level 1 DFD (Figure 3)

The Level 1 Data Flow Diagram decomposes the system into six processes and nine data stores, showing how data moves between external entities, processes, and storage.

**External Entities**: Protected Person (Wearer), Guardian / Parent (App User), Emergency Contacts, and GPS Satellites.

**Processes**:

- **Process 1.0 — Collect & Transmit Sensor Data (ESP32)**: The wearable device reads the accelerometer and GPS module, detects falls by comparing movement magnitude against the 2.5g threshold, and pushes a JSON payload containing GPS coordinates, accelerometer values, fall detection flag, and timestamp to the Firebase Realtime Database every two seconds. This process also controls the status LED on the device.

- **Process 2.0 — Handle Emergency Alerts (ESP32 + Mobile App)**: Triggered by either an SOS button press or a detected fall. The ESP32 writes an active emergency state to RTDB with the reason, trigger time, and GPS location. The mobile app streams this state and displays a red emergency banner to the guardian. When the guardian dismisses the alert, the app clears the emergency state in RTDB and logs a permanent alert record to Firestore. Deduplication logic prevents the same event from creating multiple alerts.

- **Process 3.0 — Stream Live Monitoring (Mobile App)**: The mobile app subscribes to RTDB sensor streams and renders four screens: a dashboard with GPS, movement, fall, and connectivity status cards; a GPS map with a live location marker and camera follow; a fall detection screen with animated accelerometer bars and a fall status circle; and an alert history screen showing a chronological list from Firestore.

- **Process 4.0 — Manage Geofences (Mobile App + ESP32)**: The guardian creates, edits, deletes, and toggles geofence zones on a map in the mobile app. Each zone is stored in Firestore as a polygon vertex array. When saved, the app transforms the polygon into a simplified point-plus-radius representation and syncs enabled zones to RTDB. The ESP32 reads the synced array and checks for boundary crossings every 30 seconds using the Haversine distance formula. Violations are written to RTDB and streamed back to the app.

- **Process 5.0 — Manage Emergency Contacts (Mobile App)**: The guardian performs CRUD operations on contacts stored in Firestore as a subcollection under their user document. The app displays the contact list and supports tap-to-dial for phone calls to external emergency contacts.

- **Process 6.0 — Provision Device via BLE (Mobile App + ESP32)**: During initial setup, the mobile app scans for the ESP32 device via Bluetooth Low Energy, connects via GATT, reads the device information (device ID, name, firmware version), and sends WiFi credentials to the ESP32. The ESP32 stores these credentials in its non-volatile storage (NVS) and uses them for all subsequent WiFi connections. The app registers the device ID to the user's Firestore document, creating the link between the guardian account and the wearable device.

**Data Stores**:

The system uses nine logical data stores distributed across three physical storage locations. Four reside in Firebase Realtime Database (transient, real-time data), four reside in Cloud Firestore (persistent, structured data), and one resides in the ESP32's non-volatile storage (device configuration).

| Store | Name | Location | Purpose |
|-------|------|----------|---------|
| D1 | Sensor Readings | RTDB | Live GPS, accelerometer, fall flag, and online status; overwritten every 2 seconds by the ESP32 |
| D2 | Emergency State | RTDB | Active emergency flag with reason, trigger time, and location; cleared when dismissed |
| D3 | Device Geofences | RTDB | Simplified point+radius geofence array synced from Firestore; read by ESP32 for enforcement |
| D4 | Geofence Violations | RTDB | Violation records written by ESP32 every 30-second check; streamed to the app |
| D5 | Users | Firestore | Guardian account profiles with linked device ID; created on first sign-up |
| D6 | Contacts | Firestore | Emergency contacts subcollection with name, phone, relationship, and priority flag |
| D7 | Geofence Definitions | Firestore | Source of truth for geofence zones as polygon vertex arrays with enabled status |
| D8 | Alert History | Firestore | Permanent emergency event log with type, reason, timestamp, and GPS location |
| D9 | Device Config | ESP32 NVS | WiFi SSID and password plus auto-generated device ID; survives power cycles |

### 3.3.4 Data Flow Design — Level 2 DFDs (Figures 4–8)

The Level 2 DFDs decompose five of the six Level 1 processes into their constituent sub-processes, revealing the detailed data transformations at each step.

**Process 1.0 — Collect & Transmit Sensor Data (Figure 4)**

This ESP32-side process is decomposed into four sub-processes:

- **1.1 Read Accelerometer Sensor**: Reads the MPU6050 accelerometer via the I2C bus, capturing three-axis acceleration values (ax, ay, az) in g-force units.
- **1.2 Read GPS Module**: Reads the GT-U8 GPS module via UART serial, parsing NMEA sentences to extract latitude and longitude when a fix is available.
- **1.3 Detect Falls**: Calculates the overall movement magnitude from the three accelerometer axes. If the magnitude exceeds the 2.5g threshold, sets the fall detection flag to true.
- **1.4 Push Sensor Data to Firebase**: Assembles a JSON payload containing GPS coordinates, accelerometer values, fall detection flag, online heartbeat, and a server timestamp. Pushes this payload to RTDB under the device's sensor path every two seconds. Also controls the status LED.

**Process 2.0 — Handle Emergency Alerts (Figure 5)**

This process spans both the ESP32 and the mobile app, decomposed into three sub-processes:

- **2.1 Trigger Emergency (ESP32)**: Activated by either an SOS button press or a fall detection signal from sub-process 1.3. Reads the current GPS location and writes an emergency state object to RTDB with the fields active (true), reason (e.g., "SOS button pressed" or "Fall detected"), triggeredAt timestamp, and GPS coordinates.
- **2.2 Stream Emergency to App (Mobile App)**: The mobile app listens to the RTDB emergency path via a real-time stream listener. When the active flag changes to true, it displays a red emergency banner on the dashboard and fall detection screens showing the reason and location.
- **2.3 Dismiss Emergency & Log Alert (Mobile App)**: When the guardian taps "Dismiss" or "Mark as Safe," the app writes active=false to RTDB, clearing the emergency state. Simultaneously, it creates a permanent alert document in Firestore containing the alert type, reason, message, device ID, timestamp, and GPS coordinates. Deduplication logic suppresses fall alerts occurring within three seconds of an SOS press.

**Process 3.0 — Stream Live Monitoring (Figure 6)**

This mobile app process is decomposed into four screen-rendering sub-processes, each driven by real-time data streams:

- **3.1 Render Dashboard**: Subscribes to the RTDB sensor path and renders status cards for GPS coordinates, movement data, fall detection status, and device connectivity. Displays emergency banners when an active emergency is detected.
- **3.2 Render GPS Map**: Subscribes to the RTDB GPS path and renders an OpenStreetMap with a live location marker that updates as the wearer moves. Supports auto-follow mode.
- **3.3 Render Fall Detection**: Subscribes to the RTDB accelerometer path and renders animated bars for X, Y, and Z acceleration values, plus a fall status circle (green for normal, red for fall detected). Includes a "Mark as Safe" button.
- **3.4 Render Alert History**: Queries the Firestore alerts collection ordered by timestamp and renders a chronological list with alert type icons, reasons, dates, times, and GPS locations. Includes a summary bar showing counts by alert type.

**Process 4.0 — Manage Geofences (Figure 7)**

This process spans both the mobile app and the ESP32, decomposed into three sub-processes:

- **4.1 CRUD Geofences (Mobile App)**: The guardian draws polygon boundaries on a map, assigns a name, and saves the zone. The polygon vertex array is stored in Firestore as the source of truth. The guardian can also edit, delete, or toggle each zone's enabled status.
- **4.2 Sync Geofences to Device (Mobile App)**: Triggered whenever a geofence is saved or toggled. Reads all enabled geofences from Firestore, transforms each polygon into a simplified point-plus-radius representation, and writes the resulting array to RTDB under the device path.
- **4.3 Check Geofence Violations (ESP32)**: Runs on the ESP32 every 30 seconds. Reads the synced geofence array from RTDB, calculates the Haversine distance from the current GPS position to each geofence center, and compares it against the radius. If a boundary crossing is detected, writes a violation record to RTDB with the geofence ID, name, violation type (entered or exited), GPS coordinates, distance from boundary, and timestamp.

**Process 6.0 — Provision Device via BLE (Figure 8)**

This one-time setup process spans both the mobile app and the ESP32, decomposed into four sub-processes:

- **6.1 Scan & Select Device (Mobile App)**: The guardian taps "Set Up Device" in the app, grants Bluetooth permissions, and scans for nearby BLE devices advertising with the "Guardian_" prefix. The scan results are displayed, and the guardian selects their device.
- **6.2 Establish BLE GATT Connection (Mobile App ↔ ESP32)**: The app connects to the ESP32 via BLE GATT, reads the device information characteristic (device ID, name, firmware version), and passes the guardian's WiFi credentials to the next sub-process.
- **6.3 Send WiFi Credentials (Mobile App → ESP32)**: The app writes the SSID and password to the ESP32's WiFi credentials characteristic via BLE GATT. The ESP32 stores these credentials in its non-volatile storage (NVS) and uses them to connect to WiFi.
- **6.4 Confirm Connection & Register Device (Mobile App)**: The app waits for the ESP32 to confirm successful WiFi connection via a BLE status notification. Once confirmed, the app saves the device ID to the user's Firestore document, creating the permanent link between the guardian account and the wearable device.

### 3.3.5 Database Design — Entity Relationship Diagram (Figure 9)

The system's data model spans two database paradigms: a document-collection model in Cloud Firestore for persistent data, and a hierarchical JSON tree in Firebase Realtime Database for transient, high-frequency data. The Entity Relationship Diagram models eight entities with their attributes, primary keys, foreign keys, and relationships.

**Firestore Entities (Persistent)**

- **User (D5)**: The central entity representing a registered guardian account. Primary key is `uid`, assigned by Firebase Authentication. Attributes include name, email, deviceId (foreign key linking to the RTDB Device), and account creation timestamp. All other Firestore entities are subcollections nested under the User document.

- **Contact (D6)**: An emergency contact managed by the guardian. Primary key is `contactId`, auto-generated by Firestore. Foreign key `userId` references the parent User. Attributes include name, phone number, relationship (e.g., Spouse, Sibling, Friend), and an isEmergencyContact boolean flag that determines priority display and tap-to-dial availability.

- **Geofence (D7)**: A virtual geographic boundary definition. Primary key is `geofenceId`, auto-generated by Firestore. Foreign key `userId` references the parent User. Attributes include a name, a polygon vertex array (JSON list of latitude/longitude pairs), an enabled boolean toggle, and creation/modification timestamps. This entity is the source of truth for geofence data; a simplified point-plus-radius version is cached in RTDB (D3) for on-device enforcement.

- **Alert (D8)**: A permanent historical record of an emergency event. Primary key is `alertId`, auto-generated by Firestore. Foreign keys: `userId` references the User who receives the alert, `deviceId` references the Device that triggered it. Attributes include an alert type enumeration (sos, fall, emergency), a human-readable message, a trigger reason detail, the event timestamp, and the GPS coordinates at the time of the event. Alerts are created when an active emergency state in RTDB (D2) is dismissed.

**RTDB Entities (Transient)**

- **Device**: Represents the ESP32 wearable in the Realtime Database at the path `/devices/{deviceId}/`. Primary key is `deviceId`, auto-generated from the ESP32's MAC address on first boot. Attributes include an online status (derived — not stored — from whether the last sensor update is less than 10 seconds old) and a lastSeen timestamp. The Device entity serves as the parent container for SensorReading, EmergencyState, cached geofences, and GeofenceViolation data.

- **SensorReading (D1)**: Live sensor data at `/devices/{deviceId}/sensors/`. Primary key is `sensorReadId`, auto-generated. Foreign key `deviceId` references Device. Attributes include GPS latitude and longitude, three-axis accelerometer values (X, Y, Z), a fall detection boolean flag, an online heartbeat boolean, and a server timestamp. This data is completely transient — overwritten every two seconds and never persisted to Firestore.

- **EmergencyState (D2)**: The active emergency record at `/devices/{deviceId}/emergency/`. Primary key is `emergencyStateId`, auto-generated. Foreign key `deviceId` references Device. Attributes include an active boolean flag, a trigger reason string, a triggeredAt timestamp, and the GPS coordinates at the time of activation. Only one emergency can be active per device at a time. When dismissed, the state is cleared and a permanent Alert record is created in Firestore (D8).

- **GeofenceViolation (D4)**: A real-time record of a geofence boundary crossing at `/devices/{deviceId}/geofence_violations/{timestamp}/`. Primary key is `violationId`, based on the event timestamp. Foreign keys: `deviceId` references Device, `geofenceId` references Geofence. Attributes include the geofence name at the time of violation, a violation type (entered or exited), the GPS coordinates at the violation, the distance from the boundary in meters, and a timestamp. This data is transient and stored only in RTDB — it is not synced to Firestore.

**Entity Relationships**

| Parent | Relationship | Child | Cardinality |
|--------|-------------|-------|-------------|
| User | owns | Device | One User owns zero or one Device (optional until BLE provisioning is completed) |
| User | has | Contact | One User has zero to many Contacts |
| User | defines | Geofence | One User defines zero to many Geofences |
| User | receives | Alert | One User receives zero to many Alerts |
| User | receives | GeofenceViolation | One User receives zero to many Geofence Violations |
| Device | streams | SensorReading | One Device streams exactly one set of Sensor Readings |
| Device | has | EmergencyState | One Device has zero or one active Emergency State |
| Device | generates | Alert | One Device generates zero to many Alerts |
| Device | detects | GeofenceViolation | One Device detects zero to many Geofence Violations |
| Geofence | triggers | GeofenceViolation | One Geofence triggers zero to many Geofence Violations |

**Cross-Database Relationships**: Two relationships span across Firestore and RTDB. The User-to-Device link is established through the `deviceId` field in the User document, which stores the RTDB device path identifier. The Geofence-to-GeofenceViolation link connects a Firestore geofence definition to its RTDB violation records through the `geofenceId` field. Both links are resolved at the application level rather than through database-enforced foreign key constraints.

**RTDB Hierarchical Structure**: The Device and its child entities in RTDB are organized as a hierarchical JSON tree rather than relational tables. The path `/devices/{deviceId}/` serves as the root, with sub-paths for sensors (D1), emergency (D2), cached geofences (D3), and geofence violations (D4). This structure enables efficient real-time streaming — the mobile app subscribes to specific sub-paths and receives updates instantly when data changes.

### 3.3.6 System Architecture (Figure 10)

The system follows a three-tier logical architecture with clear separation of concerns across hardware, cloud, and application layers.

**Tier 1 — Wearable Device (ESP32)**: The hardware layer worn by the protected person. It contains:
- An MPU6050 accelerometer connected via I2C for three-axis motion sensing
- A GT-U8 GPS module connected via UART serial for location tracking
- A physical SOS button on GPIO4 (active LOW) with debounce protection
- A status LED on GPIO2 indicating power, connectivity, and alert state
- A 3.7 V Li-Po battery with a TP4056 charging module, a 5 V boost converter, and a power switch between the charger and the boost converter
- WiFi connectivity for cloud communication
- Bluetooth Low Energy (BLE) for one-time device provisioning
- Non-volatile storage (NVS) for persisting WiFi credentials and device identity

The ESP32 firmware is written in Arduino C++ and runs a continuous loop: read sensors, calculate movement magnitude, check fall threshold (2.5g), assemble JSON payload, and push to Firebase RTDB every two seconds. Emergency events (SOS press or fall detection) are transmitted immediately without waiting for the next sensor interval.

**Tier 2 — Firebase Cloud**: The backend layer providing three Firebase services:
- **Firebase Authentication**: Email/password authentication for guardian accounts. The auth state change stream gates access to the mobile app's home screen.
- **Firebase Realtime Database (RTDB)**: Handles all transient, high-frequency data. The ESP32 writes sensor data every two seconds. The mobile app subscribes to stream listeners for real-time updates. RTDB is used for data that changes constantly and does not need long-term persistence: sensor readings, emergency state, cached geofences, and geofence violations.
- **Cloud Firestore**: Handles all persistent, structured data. User profiles, contacts, geofence definitions, and alert history are stored as document collections under each user account. Firestore is the source of truth for configuration data and the permanent log for emergency events.

**Tier 3 — Mobile Application (Flutter)**: The presentation layer used by the guardian. Built with Flutter for cross-platform deployment (Android and iOS). The app uses a singleton FirebaseService class as the single entry point for all cloud operations. The user interface follows Material Design 3 with a deep blue primary color scheme and the Nunito font family. Navigation uses a bottom navigation bar with six tabs: Dashboard, Map, Sensors (Fall Detection), Alerts, Geofences, and Contacts. The app uses OpenStreetMap via the flutter_map library for GPS mapping, eliminating the need for paid API keys.

**Communication Flows**:
- ESP32 → Firebase RTDB: Sensor data (every 2 seconds), emergency state (on event), geofence violations (every 30 seconds)
- Firebase RTDB → Mobile App: Real-time stream listeners for sensor data, emergency state, and violation notifications
- Mobile App → Firebase Firestore: CRUD operations for contacts, geofence definitions, and alert logging
- Mobile App ↔ ESP32 (BLE): One-time device provisioning to exchange device info and WiFi credentials

### 3.3.7 User Interface Design

The mobile application presents six tab-based screens accessible through a bottom navigation bar:

**Dashboard Tab (Home)**: The default screen upon login. Displays four status cards in a grid layout: GPS coordinates (latitude and longitude), movement status (active or stationary based on accelerometer magnitude), fall detection status (normal or fall detected with a colored indicator), and device connectivity (online or offline with a last-seen timestamp). An emergency banner appears at the top when an alert is active, colored red, with the alert reason and an inline dismiss button.

**Map Tab**: Renders an OpenStreetMap using the flutter_map library with a live location marker representing the wearer's current position. The marker updates in real time as GPS coordinates stream from RTDB. An auto-follow toggle keeps the map centered on the moving marker.

**Sensors Tab (Fall Detection)**: Displays three vertical animated bars for real-time X, Y, and Z accelerometer values, color-coded for visual clarity. A large circular indicator shows fall status — green for normal, red for fall detected. A "Mark as Safe" button allows the guardian to clear an active fall alert.

**Alerts Tab**: Shows a summary bar at the top with counts of alerts grouped by type (SOS, fall, geofence). Below it, a scrollable list displays past alerts in reverse chronological order. Each list entry shows an icon representing the alert type, the reason or message, the date and time formatted for readability, and the GPS location at the time of the event. An empty state message is shown when no alerts exist.

**Geofences Tab**: Displays a list of saved geofence zones, each with its name, a colored indicator for enabled/disabled status, and a toggle switch. A floating action button opens the geofence creation screen where the guardian draws a polygon on a map and assigns a name. Existing zones can be edited or deleted. Violation history for each zone is accessible from this screen.

**Contacts Tab**: Displays a list of emergency contacts, each showing the contact's name, phone number, relationship, and an emergency priority indicator. Contacts flagged as emergency contacts appear in a prioritized section at the top. Tapping a contact during an active emergency initiates a phone call. A floating action button opens the contact creation form with fields for name, phone number, relationship, and emergency priority toggle.

**Auth Screen**: Shown when no user is authenticated. Provides email and password fields for sign-in, a link to the registration screen, and a password reset option.

**Device Setup Flow**: A dedicated setup wizard accessed from the app settings. Guides the guardian through BLE permissions, device scanning and selection, WiFi credential entry, and provisioning status feedback.

---

## 3.4 System Development

### 3.4.1 Hardware Components

The wearable device is built from the following hardware components:

| Component | Model | Interface | Purpose |
|-----------|-------|-----------|---------|
| Microcontroller | ESP32-S3 SuperMini | — | Main processing unit with built-in WiFi and Bluetooth |
| Accelerometer | MPU6050 | I2C | Three-axis motion and acceleration sensing |
| GPS Module | GT-U8 | UART Serial | Satellite-based location tracking |
| SOS Button | Tactile push button | GPIO4 (active LOW) | Manual emergency activation by the wearer |
| Status LED | Single-color LED | GPIO2 | Visual feedback for power, connectivity, and alert state |
| Battery | Li-Po 3.7 V (1000 mAh) | — | Rechargeable power source |
| Charging Module | TP4056 (protected, USB-C) | — | Charges the battery at 1 A |
| Boost Converter | Mini DC-DC boost (set to 5 V) | — | Steps 3.7 V up to a stable 5 V for the ESP32 |
| Power Switch | SPST slide switch | — | Cuts power between the charging module and the boost converter |

### 3.4.2 Software Tools and Technologies

| Technology | Version / Type | Purpose |
|------------|---------------|---------|
| Flutter SDK | Latest stable | Cross-platform mobile application framework |
| Dart | — | Programming language for the Flutter application |
| Arduino IDE | — | Development environment for ESP32 firmware |
| Arduino C++ | — | Programming language for ESP32 firmware |
| Firebase Authentication | — | User sign-in and session management |
| Firebase Realtime Database | — | Real-time transient data streaming |
| Cloud Firestore | — | Persistent structured data storage |
| Visual Studio Code | — | Primary code editor and IDE |
| Git | — | Version control |

### 3.4.3 Firmware Libraries and Dependencies

The ESP32 firmware relies on the following Arduino libraries:

| Library | Purpose |
|---------|---------|
| Firebase ESP32 Client (mobizt) | Firebase RTDB connectivity and authentication |
| TinyGPS++ | NMEA sentence parsing for GPS data extraction |
| MPU6050 (Electronic Cats) | I2C communication with the accelerometer |
| ArduinoJson | JSON payload construction and parsing |
| WiFi (built-in) | ESP32 WiFi station mode connectivity |
| BLE (built-in) | Bluetooth Low Energy GATT server for device provisioning |

### 3.4.4 Mobile Application Libraries and Dependencies

The Flutter application relies on the following packages:

| Package | Purpose |
|---------|---------|
| firebase_core | Firebase platform initialization |
| firebase_auth | Email/password authentication |
| firebase_database | RTDB real-time stream listeners |
| cloud_firestore | Firestore CRUD operations |
| flutter_map | OpenStreetMap rendering with live markers |
| flutter_map_cancellable_tile_provider | Efficient map tile loading and cancellation |
| flutter_blue_plus | BLE scanning, connection, and GATT communication for device provisioning |
| url_launcher | Tap-to-dial phone call initiation |
| google_fonts | Nunito font family for Material Design 3 typography |

### 3.4.5 Implementation Highlights

**FirebaseService Singleton Pattern**: All Firebase operations in the mobile app are routed through a single `FirebaseService` singleton class, accessed as `FirebaseService()` anywhere in the application. This ensures consistent initialization, prevents duplicate connections, and centralizes error handling. The singleton provides methods for authentication (signIn, register, signOut, resetPassword), RTDB operations (listenToDeviceData, listenToEmergencyAlert, clearEmergency), and Firestore operations (CRUD for contacts, geofences, and alerts).

**Authentication Gating**: The app's entry point uses an AuthGate widget that listens to Firebase Authentication state changes. When unauthenticated, the AuthScreen is shown. When authenticated, the HomeScreen with its six-tab navigation is shown. A loading spinner is displayed while Firebase initializes.

**Real-Time Data Model**: Sensor data from RTDB is parsed into a `DeviceData` model object. The model computes derived values: accelerometer magnitude from the three axis values, online/offline status from timestamp staleness (threshold: 10 seconds), and a human-readable last-seen label. The model supports `copyWith` for immutable state updates.

**Geofence Enforcement Algorithm**: The ESP32 enforces geofences using the Haversine distance formula. Rather than performing computationally expensive point-in-polygon checks, the mobile app pre-processes polygon vertices into a center point (calculated as the average of all vertices) and a radius (calculated as the maximum distance from the center to any vertex). The ESP32 then performs a simple distance comparison between the current GPS position and each geofence's center point.

**Fall Detection Algorithm**: The ESP32 calculates the overall acceleration magnitude using the formula:

```
magnitude = sqrt(ax² + ay² + az²)
```

If the magnitude exceeds the configurable threshold of 2.5g, a fall is detected. The fall flag is reset after a five-second cooldown period to prevent repeated triggers from the same event.

**Emergency Deduplication**: Multiple layers prevent duplicate alerts. The ESP32 guards against re-triggering when an emergency is already active. The mobile app suppresses fall alerts that occur within three seconds of an SOS button press (the SOS takes priority). Alerts are deduplicated by their triggeredAt timestamp.

**Offline Detection**: Device online status is not stored as a separate field or heartbeat signal. Instead, the app derives online status by comparing the device's last sensor timestamp against the current time. If the last update is more than 10 seconds old, the device is displayed as offline. This approach eliminates the need for a separate heartbeat mechanism while still providing timely offline awareness.

**BLE Device Provisioning**: During initial setup, the mobile app scans for BLE devices advertising with the "Guardian_" prefix. Upon connection, a five-step GATT protocol executes: connect to the device, read the device information characteristic (device ID, name, firmware version), subscribe to the status notification characteristic, write WiFi credentials (SSID and password) to the credentials characteristic, and wait for a "connected" status notification confirming the ESP32 has successfully joined the WiFi network. The device ID is then saved to the user's Firestore document to establish the permanent link.

---

## 3.5 System Testing

### 3.5.1 Testing Strategy

The system was tested at four levels to ensure functionality, integration, and reliability:

**Unit Testing**: Individual functions and methods were tested in isolation. On the Flutter side, the project uses the `flutter_test` package for widget and unit tests. On the ESP32 side, individual sensor reading functions, GPS parsing logic, and fall detection calculations were tested with known inputs and expected outputs.

**Integration Testing**: Communication pathways between components were tested end-to-end. Key integration tests included: ESP32 to Firebase RTDB data transmission and verification; RTDB stream listener to Flutter UI data binding; Firestore CRUD operations from the Flutter app; BLE GATT communication between the Flutter app and ESP32 during device provisioning; and the emergency alert lifecycle from SOS button press to app notification to dismissal and logging.

**System Testing**: The complete system was tested as a whole to verify that all use cases function correctly. Each of the ten use cases was tested against its defined normal flow and alternative flows:

| Use Case | Key Test Scenario |
|----------|------------------|
| UC01 — View Dashboard | Verify that sensor data appears on the dashboard within two seconds of device transmission |
| UC02 — View GPS Map | Verify that the map marker updates as the wearer moves and auto-follow functions correctly |
| UC03 — Monitor Fall Detection | Verify that accelerometer bars animate in real time and fall status circle changes on detection |
| UC04 — Manage Geofences | Verify that creating a geofence syncs to the device and violations are detected and logged |
| UC05 — Manage Contacts | Verify that contacts can be created, edited, and deleted; tap-to-dial initiates a phone call |
| UC06 — View Alert History | Verify that dismissed alerts appear in the history list with correct type, time, and location |
| UC07 — Trigger SOS | Verify that SOS button press sends an immediate alert with current GPS location |
| UC08 — Generate Sensor Data | Verify that sensor data is generated continuously at two-second intervals |
| UC09 — Stream Sensor Data | Verify that real-time data reaches the app without polling or manual refresh |
| UC10 — Store Persistent Data | Verify that contacts, geofences, and alert history persist across app restarts |

**Acceptance Testing**: The system was validated against the original requirements: real-time monitoring capability, emergency alerting with location, geofence enforcement, contact management, and ease of device setup.

### 3.5.2 Test Cases for Critical Functions

**Fall Detection Test**: The wearable device was subjected to controlled acceleration events exceeding the 2.5g threshold to verify fall detection triggering. Normal daily movements (walking, sitting, bending) were also tested to confirm they do not generate false positives.

**SOS Button Test**: The SOS button was pressed under various conditions: with valid GPS fix, without GPS fix, and while an emergency was already active. The system correctly sent alerts with current location when available, fell back to last known location when GPS was unavailable, and suppressed duplicate alerts when an emergency was already active.

**Geofence Violation Test**: A geofence zone was defined around a known location. The wearable device was physically moved inside and outside the boundary. The system correctly detected entry and exit events, logged violation records to RTDB, and streamed them to the mobile app within the 30-second enforcement interval.

**Offline Detection Test**: The wearable device was powered off while the mobile app was monitoring. Within 10 seconds of the last sensor transmission, the app displayed the device as offline with an appropriate visual indicator.

**BLE Provisioning Test**: The device setup wizard was tested with correct and incorrect WiFi credentials. Successful provisioning resulted in the device connecting to WiFi and the device ID being registered to the user account. Failed provisioning displayed an appropriate error message and allowed retry.

---

## 3.6 Summary

This chapter presented the methodology employed in developing the GuardianNako IoT Wearable Protection System. The iterative and incremental approach enabled parallel development of the three system tiers — ESP32 firmware, Firebase cloud backend, and Flutter mobile application — with continuous integration testing at each stage.

System analysis produced a set of ten functional use cases organized into four groups (monitoring, managing, emergency, and device-side) supported by two background services for data streaming and persistent storage. Non-functional requirements addressed real-time responsiveness, reliability, usability, affordability, offline awareness, and alert deduplication.

System design produced a context diagram establishing the system boundary with five external entities, a use case diagram modeling actor interactions, a Level 1 data flow diagram with six processes and nine logical data stores, five Level 2 diagrams decomposing the major processes, an entity relationship diagram spanning Firestore and RTDB with eight entities and ten relationships, a three-tier system architecture separating hardware, cloud, and application concerns, and a six-tab user interface design for the mobile application.

System development detailed the hardware components (ESP32, MPU6050, GT-U8 GPS, SOS button, status LED), the software tools and technologies (Flutter, Dart, Arduino C++, Firebase), the firmware and application library dependencies, and implementation highlights including the FirebaseService singleton pattern, authentication gating, the real-time data model, geofence enforcement and fall detection algorithms, emergency deduplication, offline detection, and BLE device provisioning.

System testing covered four levels — unit, integration, system, and acceptance — with specific test scenarios for each use case and dedicated test cases for the five critical functions: fall detection, SOS button, geofence violation, offline detection, and BLE provisioning.
