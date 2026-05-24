# UC09 — Stream Sensor Data

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC09 |
| **Use Case Name** | Stream Sensor Data |
| **Actor(s)** | System (supporting — Firebase Realtime Database) |
| **Description** | The live data channel that carries sensor readings and emergency state from the wearable device to the guardian's app in real time. |
| **Precondition** | The ESP32 device is connected and writing data. |
| **Postcondition** | The guardian's app receives continuous real-time updates without polling or manual refresh. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | ESP32 | Send | Sends sensor data (motion, GPS, fall status) to the live data channel every 2 seconds. |
| 2 | ESP32 | Send | Sends emergency state changes (active, reason, location) to the live data channel immediately when they occur. |
| 3 | System | Push | The live data channel pushes each update to the guardian's app instantly. |
| 4 | App | Receive | Receives each update and refreshes the relevant screens (Dashboard, Map, Fall Detection). |

| **Included by** | UC01 (View Dashboard), UC02 (View Live GPS Map), UC03 (Monitor Fall Detection), UC07 (Trigger SOS), UC08 (Generate Sensor Data) |
