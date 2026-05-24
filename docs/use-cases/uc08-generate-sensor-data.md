# UC08 — Generate Sensor Data

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC08 |
| **Use Case Name** | Generate Sensor Data |
| **Actor(s)** | Protected Person (Wearer) |
| **Description** | As the protected person moves throughout their day, the wearable device continuously captures motion and location data and streams it to the cloud. This data powers the guardian's entire monitoring view. |
| **Precondition** | The ESP32 device is powered on, connected to WiFi, and being worn. |
| **Postcondition** | Live sensor data — accelerometer readings, GPS location, fall status, and device online status — is continuously available to the guardian's app. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | ESP32 | Read | Reads the accelerometer to capture the wearer's current motion (X, Y, Z axis values). |
| 2 | ESP32 | Read | Reads the GPS module to capture the wearer's current location. |
| 3 | ESP32 | Calculate | Calculates the overall movement magnitude from the accelerometer readings. |
| 4 | ESP32 | Check | Checks whether the movement magnitude exceeds the fall threshold. If it does, sets the fall detection flag to true. |
| 5 | ESP32 | Send | Sends all sensor readings — motion, location, fall status, and a timestamp — to the cloud every 2 seconds. |
| 6 | System | Deliver | The guardian's app receives the updated sensor data and refreshes the Dashboard, Map, and Fall Detection screens. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 4a | Fall detected (magnitude exceeds threshold) | Trigger | ESP32 triggers the emergency alert flow (see UC07). A 5-second cooldown prevents repeated triggers from the same fall. |
| 5a | WiFi is disconnected | Fail | Data cannot be sent. After 10 seconds without an update, the guardian's app shows the device as offline. |

| **Includes** | UC09 — Stream Sensor Data |
| **Extends** | UC07 — Trigger SOS (a detected fall automatically triggers an emergency) |
