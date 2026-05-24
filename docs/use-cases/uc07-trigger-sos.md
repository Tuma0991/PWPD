# UC07 — Trigger SOS

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC07 |
| **Use Case Name** | Trigger SOS |
| **Actor(s)** | Protected Person (Wearer) |
| **Description** | The protected person presses the physical SOS button on the wearable device to immediately alert the guardian that they need help. |
| **Precondition** | The ESP32 device is powered on, connected to WiFi, and being worn. |
| **Postcondition** | An emergency alert is sent to the guardian's app with the wearer's current location. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Wearer | Press | Presses and holds the SOS button on the device. |
| 2 | ESP32 | Detect | Detects the button press (with debounce to prevent false triggers). |
| 3 | ESP32 | Read | Reads the current GPS location. |
| 4 | ESP32 | Send | Immediately sends an emergency alert with the reason "SOS button pressed," the current location, and the time. |
| 5 | ESP32 | Indicate | The status LED changes to indicate an alert is active. |
| 6 | System | Deliver | The guardian's app receives the emergency alert and displays a red banner with the reason and location. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 4a | An emergency is already active | Skip | ESP32 does not send a duplicate alert. |
| 4b | No GPS fix available | Fallback | ESP32 sends the alert with the last known location, marked accordingly. |

| **Includes** | UC09 — Stream Sensor Data |
| **Extended by** | UC08 — Generate Sensor Data (a detected fall automatically triggers an emergency) |
