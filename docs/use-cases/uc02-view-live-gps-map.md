# UC02 — View Live GPS Map

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC02 |
| **Use Case Name** | View Live GPS Map |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian views the protected person's real-time location on a map. |
| **Precondition** | The guardian is logged in, a device is paired, and the device has a GPS fix. |
| **Postcondition** | The map shows the device's current location with a live-updating marker. |

**Normal Flow**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Navigate | Navigates to the Map tab. |
| 2 | System | Display | Displays a map with the protected person's current location marked. |
| 3 | System | Update | Updates the marker position in real time as the device moves. |
| 4 | System | Track | The map camera automatically follows the moving marker. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 2a | Device is offline or has no GPS fix | Fallback | Map shows the last known location, or a default view if no previous location exists. |

| **Includes** | UC09 — Stream Sensor Data |
